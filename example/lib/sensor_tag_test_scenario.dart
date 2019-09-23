import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_ble_lib/flutter_ble_lib.dart';

typedef Logger = Function(String);

abstract class SensorTagTemperatureUuids {
  static const String temperatureService =
      "F000AA00-0451-4000-B000-000000000000";
  static const String temperatureData = "F000AA01-0451-4000-B000-000000000000";
  static const String temperatureConfig =
      "F000AA02-0451-4000-B000-000000000000";
}

class TestScenario {
  BleManager bleManager = BleManager.getInstance();
  bool deviceConnectionAttempted = false;
  StreamSubscription monitoringStreamSubscription;

  Future<void> runTestScenario(Logger log, Logger logError) async {
    log("CREATING CLIENT...");
    await bleManager.createClient(
        restoreStateIdentifier: "5",
        restoreStateAction: (devices) {
          log("RESTORED DEVICES: $devices");
        });

    log("CREATED CLIENT");
    log("STARTING SCAN...");
    log("Looking for Sensor Tag...");

    bleManager.startPeripheralScan().listen((scanResult) async {
      log("RECEIVED SCAN RESULT: "
          "\n name: ${scanResult.peripheral.name}"
          "\n identifier: ${scanResult.peripheral.identifier}"
          "\n rssi: ${scanResult.rssi}");

      if (scanResult.peripheral.name == "SensorTag" &&
          !deviceConnectionAttempted) {
        log("Sensor Tag found!");
        deviceConnectionAttempted = true;
        log("Stopping device scan...");
        await bleManager.stopDeviceScan();
        return _tryToConnect(scanResult.peripheral, log, logError);
      }
    }, onError: (error) {
      logError(error);
    });
  }

  Future<void> _tryToConnect(
      Peripheral peripheral, Logger log, Logger logError) async {
    log("OBSERVING connection state \nfor ${peripheral.name},"
        " ${peripheral.identifier}...");

    peripheral
        .observeConnectionState(emitCurrentValue: true)
        .listen((connectionState) {
      log("Current connection state is: \n $connectionState");
      if (connectionState == PeripheralConnectionState.disconnected) {
        log("${peripheral.name} has DISCONNECTED");
      }
    });

    log("CONNECTING to ${peripheral.name}, ${peripheral.identifier}...");
    await peripheral.connect();
    log("CONNECTED to ${peripheral.name}, ${peripheral.identifier}!");
    deviceConnectionAttempted = false;

    monitoringStreamSubscription?.cancel();
    monitoringStreamSubscription = peripheral
        .monitorCharacteristic(SensorTagTemperatureUuids.temperatureService,
            SensorTagTemperatureUuids.temperatureConfig)
        .listen(
      (characteristic) {
        log("Characteristic ${characteristic.uuid} changed. New value: ${characteristic.value}");
      },
      onError: (error) {
        log("Error when trying to modify characteristic value. $error");
      },
    );

    peripheral
        .discoverAllServicesAndCharacteristics()
        .then((_) => peripheral.services())
        .then((services) {
          log("PRINTING SERVICES for ${peripheral.name}");
          services.forEach((service) => log("Found service ${service.uuid}"));
          return services.first;
        })
        .then((service) async {
          log("PRINTING CHARACTERISTICS FOR SERVICE \n${service.uuid}");
          List<Characteristic> characteristics =
              await service.characteristics();
          characteristics.forEach((characteristic) {
            log("${characteristic.uuid}");
          });

          log("PRINTING CHARACTERISTICS FROM \nPERIPHERAL for the same service");
          return peripheral.characteristics(service.uuid);
        })
        .then((characteristics) => characteristics.forEach((characteristic) =>
            log("Found characteristic \n ${characteristic.uuid}")))
        .then((_) {
          log("Turn off temperature update");
          return peripheral.writeCharacteristic(
              SensorTagTemperatureUuids.temperatureService,
              SensorTagTemperatureUuids.temperatureConfig,
              Uint8List.fromList([0]),
              false);
        })
        .then((_) {
          return peripheral.readCharacteristic(
              SensorTagTemperatureUuids.temperatureService,
              SensorTagTemperatureUuids.temperatureData);
        })
        .then((data) {
          log("Temperature value ${data.value}");
        })
        .then((_) {
          log("Turn on temperature update");
          return peripheral.writeCharacteristic(
              SensorTagTemperatureUuids.temperatureService,
              SensorTagTemperatureUuids.temperatureConfig,
              Uint8List.fromList([1]),
              false);
        })
        .then((_) => Future.delayed(Duration(seconds: 1)))
        .then((_) {
          return peripheral.readCharacteristic(
              SensorTagTemperatureUuids.temperatureService,
              SensorTagTemperatureUuids.temperatureData);
        })
        .then((data) {
          log("Temperature value ${data.value}");
        })
        .then((_) {
          log("WAITING 10 SECOND BEFORE DISCONNECTING");
          return Future.delayed(Duration(seconds: 10));
        })
        .then((_) {
          log("DISCONNECTING...");
          return peripheral.disconnectOrCancelConnection();
        })
        .then((_) {
          log("Disconnected!");
          log("WAITING 10 SECOND BEFORE DESTROYING CLIENT");
          return Future.delayed(Duration(seconds: 10));
        })
        .then((_) {
          log("DESTROYING client...");
          return bleManager.destroyClient();
        })
        .then((_) => log("\BleClient destroyed after a delay"));
  }
}