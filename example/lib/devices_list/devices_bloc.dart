import 'dart:async';
import 'dart:io';

import 'package:fimber/fimber.dart';
import 'package:flutter_ble_lib_example/model/ble_device.dart';
import 'package:flutter_ble_lib_example/repository/device_repository.dart';
import 'package:flutter_ble_lib/flutter_ble_lib.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:rxdart/rxdart.dart';

import '../sensor_tag_config.dart';

class DevicesBloc {
  final List<BleDevice> bleDevices = <BleDevice>[];

  BehaviorSubject<List<BleDevice>> _visibleDevicesController = BehaviorSubject<List<BleDevice>>.seeded(<BleDevice>[]);

  StreamController<BleDevice> _devicePickerController = StreamController<BleDevice>();

  StreamSubscription<ScanResult> _scanSubscription;
  StreamSubscription _devicePickerSubscription;

  ValueObservable<List<BleDevice>> get visibleDevices => _visibleDevicesController.stream;

  Sink<BleDevice> get devicePicker => _devicePickerController.sink;

  DeviceRepository _deviceRepository;
  BleManager _bleManager;
  PermissionStatus _locationPermissionStatus = PermissionStatus.unknown;

  Stream<BleDevice> get pickedDevice => _deviceRepository.pickedDevice.skipWhile((bleDevice) => bleDevice == null);

  DevicesBloc(this._deviceRepository, this._bleManager);

  void _handlePickedDevice(BleDevice bleDevice) {
    _deviceRepository.pickDevice(bleDevice);
  }

  void dispose() {
    Fimber.d("cancel _devicePickerSubscription");
    _devicePickerSubscription.cancel();
    _visibleDevicesController.close();
    _devicePickerController.close();
    _scanSubscription?.cancel();
  }

  void dispose2() {
    _scanSubscription?.cancel();
  }

  void init(log, BehaviorSubject<BleDevice> deviceController, BehaviorSubject<PeripheralConnectionState> connectionStateController) {
    Fimber.d("Init devices bloc");
    bleDevices.clear();
    _bleManager
        .createClient(
            restoreStateIdentifier: "example-restore-state-identifier",
            restoreStateAction: (peripherals) {
              peripherals?.forEach((peripheral) {
                Fimber.d("Restored peripheral: ${peripheral.name}");
              });
            })
        .catchError((e) => Fimber.d("Couldn't create BLE client", ex: e))
        .then((_) => _checkPermissions())
        .catchError((e) => Fimber.d("Permission check error", ex: e))
        .then((_) => _waitForBluetoothPoweredOn(log, deviceController, connectionStateController))
        .then((_) => _startScan(log, deviceController, connectionStateController));

    if (_visibleDevicesController.isClosed) {
      _visibleDevicesController = BehaviorSubject<List<BleDevice>>.seeded(<BleDevice>[]);
    }

    if (_devicePickerController.isClosed) {
      _devicePickerController = StreamController<BleDevice>();
    }

    Fimber.d(" listen to _devicePickerController.stream");
    _devicePickerSubscription = _devicePickerController.stream.listen(_handlePickedDevice);
  }

  Future<void> _checkPermissions() async {
    if (Platform.isAndroid) {
      var permissionStatus = await PermissionHandler().requestPermissions([PermissionGroup.location]);

      _locationPermissionStatus = permissionStatus[PermissionGroup.location];

      if (_locationPermissionStatus != PermissionStatus.granted) {
        return Future.error(Exception("Location permission not granted"));
      }
    }
  }

  Future<void> _waitForBluetoothPoweredOn(log, BehaviorSubject<BleDevice> deviceController, BehaviorSubject<PeripheralConnectionState> connectionStateController) async {
    Completer completer = Completer();
    StreamSubscription<BluetoothState> subscription;
    subscription = _bleManager.observeBluetoothState(emitCurrentValue: true).listen((bluetoothState) async {
      if (bluetoothState == BluetoothState.POWERED_ON && !completer.isCompleted) {
        log('Bluetooth Powered on');
        //await subscription.cancel();
        bleDevices.clear();
        completer.complete();
        _startScan(log, deviceController, connectionStateController);
      } else if (bluetoothState == BluetoothState.POWERED_OFF) {
        log('Bluetooth Powered off');
        bleDevices.clear();
        completer = Completer();
        dispose2();
      }
    });

    return completer.future;
  }

  void _startScan(log, BehaviorSubject<BleDevice> deviceController, BehaviorSubject<PeripheralConnectionState> connectionStateController) {
    log("Ble client created");
    log("Ble starting scan");
    _scanSubscription = _bleManager.startPeripheralScan().listen((ScanResult scanResult) async {
      var bleDevice = BleDevice(scanResult);
      if (scanResult.advertisementData.localName != null && !bleDevices.contains(bleDevice)) {
        log('found new device ${scanResult.advertisementData.localName} ${scanResult.peripheral.identifier}');
        bleDevices.add(bleDevice);
        _visibleDevicesController.add(bleDevices.sublist(0));

        if (bleDevice.name == "HarpBT190300636") {

          await stopScan();

          deviceController = BehaviorSubject<BleDevice>.seeded(bleDevice);

          deviceController.stream.listen((bleDevice) async {
            var peripheral = bleDevice.peripheral;

            peripheral.observeConnectionState(emitCurrentValue: true, completeOnDisconnect: true).listen((connectionState) async {
              log('Observed new connection state: \n$connectionState');
              connectionStateController.add(connectionState);
            });

            try {
              if (await peripheral.isConnected()) {
                log("Already Connected to ${peripheral.name}");
              } else {
                log("Connecting to ${peripheral.name}");
                await peripheral.connect();
                log("Connected!");

                await peripheral.discoverAllServicesAndCharacteristics().then((_) => peripheral.services()).then((services) {
                  log("PRINTING SERVICES for ${peripheral.name}");
                  var srv = services.firstWhere((service) => service.uuid == SensorTagTemperatureUuids.temperatureService.toLowerCase());
                  return srv;
                }).then((service) async {
                  service.monitorCharacteristic(SensorTagTemperatureUuids.temperatureDataCharacteristic, transactionId: "ignitionOn").listen((event) {
                    if (event.value.toString().contains("[0]")) {
                      log("Ignition Off");
                    } else if (event.value.toString().contains("[1]")) {
                      log("Ignition On");
                    } else {
                      log("Ignition - No Event Recorded");
                    }
                  });
                });
              }

              //await service.writeCharacteristic(SensorTagTemperatureUuids.temperatureConfigCharacteristic, Uint8List.fromList([valueToSave]), false);

              //Fimber.d("Written \"$valueToSave\" to temperature config");
            } on BleError catch (e) {
              log(e.toString());

              if (await deviceController.stream.value.peripheral.isConnected()) {
                log("DISCONNECTING...");
                await deviceController.stream.value.peripheral.disconnectOrCancelConnection();
              }
              log("Disconnected!");
            }
          });
        }
      }
    });
  }

  Future<void> stopScan() async {
    await _bleManager.stopPeripheralScan();
  }

  void _startScan2() {
    Fimber.d("Ble client created");
    _scanSubscription = _bleManager.startPeripheralScan().listen((ScanResult scanResult) {
      var bleDevice = BleDevice(scanResult);
      if (scanResult.advertisementData.localName != null && !bleDevices.contains(bleDevice)) {
        Fimber.d('found new device ${scanResult.advertisementData.localName} ${scanResult.peripheral.identifier}');
        bleDevices.add(bleDevice);
        _visibleDevicesController.add(bleDevices.sublist(0));
      }
    });
  }

  Future<void> refresh() async {
    _scanSubscription.cancel();
    await _bleManager.stopPeripheralScan();
    bleDevices.clear();
    _visibleDevicesController.add(bleDevices.sublist(0));
    await _checkPermissions().then((_) => _startScan2()).catchError((e) => Fimber.d("Couldn't refresh", ex: e));
  }
}
