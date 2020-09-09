import 'dart:async';
import 'dart:typed_data';

import 'package:fimber/fimber.dart';
import 'package:flutter/material.dart';
import 'package:flutter_ble_lib_example/device_details/device_details_bloc.dart';
import 'package:flutter_ble_lib_example/device_details/view/logs_container_view.dart';

import 'package:flutter_ble_lib_example/model/ble_device.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_ble_lib/flutter_ble_lib.dart';
import 'package:flutter_ble_lib_example/test_scenarios/test_scenarios.dart';
import 'package:rxdart/rxdart.dart';

import '../sensor_tag_config.dart';
import 'devices_bloc.dart';
import 'devices_bloc_provider.dart';
import 'hex_painter.dart';
import 'package:location/location.dart';

typedef DeviceTapListener = void Function();

class DevicesListScreen extends StatefulWidget {
  @override
  State<DevicesListScreen> createState() => DeviceListScreenState();
}

class DeviceListScreenState extends State<DevicesListScreen> {
  DevicesBloc _devicesBloc;
  StreamSubscription _appStateSubscription;
  bool _shouldRunOnResume = true;
  BleManager bleManager = BleManager();
  bool deviceConnectionAttempted = false;

  BehaviorSubject<BleDevice> _deviceController;

  ValueObservable<BleDevice> get device => _deviceController.stream;

  BehaviorSubject<PeripheralConnectionState> _connectionStateController = BehaviorSubject<PeripheralConnectionState>.seeded(PeripheralConnectionState.disconnected);

  Location location = new Location();

  bool _serviceEnabled;
  PermissionStatus _permissionGranted;
  LocationData _locationData;

  Subject<List<DebugLog>> _logsController;

  Observable<List<DebugLog>> get logs => _logsController.stream;

  List<DebugLog> _logs = [];
  Logger log;
  Logger logError;

  BleManager _bleManager = BleManager();

  @override
  void didUpdateWidget(DevicesListScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    Fimber.d("didUpdateWidget");
  }

  void _onPause() {
    Fimber.d("onPause");
    _appStateSubscription.cancel();
    _devicesBloc.dispose();
  }

  Future<void> _onResume() async {
    log("onResume");

    // _serviceEnabled = await location.serviceEnabled();
    // if (!_serviceEnabled) {
    //   _serviceEnabled = await location.requestService();
    //   if (!_serviceEnabled) {
    //     return;
    //   }
    // }

    // _permissionGranted = await location.hasPermission();
    // if (_permissionGranted == PermissionStatus.denied) {
    //   _permissionGranted = await location.requestPermission();
    //   if (_permissionGranted != PermissionStatus.granted) {
    //     return;
    //   }
    // }
    // log("Getting Current Location Data");

    // _locationData = await location.getLocation();

    // log("Getting Current Location Data - Done");

    // location.onLocationChanged.listen((LocationData currentLocation) {
    //   log("Getting Continuous Location Data: \n$currentLocation.");
    // });

    _devicesBloc.init(log, _deviceController, _connectionStateController);

    // _appStateSubscription = _devicesBloc.pickedDevice.listen((bleDevice) async {
    //   log("navigating to selected device");

    //   await _devicesBloc.stopScan();
    //   //_onPause();

    //   //await Navigator.pushNamed(context, "/details");
    //   //setState(() {
    //   //  _shouldRunOnResume = true;
    //   // });
    //   //  Fimber.d("back from details");
    // });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    Fimber.d("DeviceListScreenState didChangeDependencies");
    if (_devicesBloc == null) {
      _devicesBloc = DevicesBlocProvider.of(context);
      if (_shouldRunOnResume) {
        _shouldRunOnResume = false;
        _onResume();
      }
    }
  }

  @override
  void initState() {
    super.initState();

    _logsController = PublishSubject<List<DebugLog>>();

    log = (text) {
      var now = DateTime.now();
      _logs.insert(
          0,
          DebugLog(
            '${now.hour}:${now.minute}:${now.second}.${now.millisecond}',
            text,
          ));
      Fimber.d(text);
      _logsController.add(_logs);
    };

    logError = (text) {
      _logs.insert(0, DebugLog(DateTime.now().toString(), "ERROR: $text"));
      Fimber.e(text);
      _logsController.add(_logs);
    };
  }

  @override
  Widget build(BuildContext context) {
    Fimber.d("build DeviceListScreenState");
    if (_shouldRunOnResume) {
      _shouldRunOnResume = false;
      _onResume();
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('Bluetooth devices'),
      ),
      body: Column(
        children: [
          Expanded(
            flex: 3,
            child: StreamBuilder<List<BleDevice>>(
              initialData: _devicesBloc.visibleDevices.value,
              stream: _devicesBloc.visibleDevices,
              builder: (context, snapshot) => RefreshIndicator(
                onRefresh: _devicesBloc.refresh,
                child: DevicesList(_devicesBloc, snapshot.data),
              ),
            ),
          ),
          Expanded(
            flex: 7,
            child: LogsContainerView(logs),
          )
        ],
      ),
    );
  }

  @override
  void dispose() {
    Fimber.d("Dispose DeviceListScreenState");
    _onPause();

    super.dispose();
  }

  @override
  void deactivate() {
    print("deactivate");
    super.deactivate();
  }

  @override
  void reassemble() {
    Fimber.d("reassemble");
    super.reassemble();
  }
}

class DevicesList extends ListView {
  DevicesList(DevicesBloc devicesBloc, List<BleDevice> devices)
      : super.separated(
            separatorBuilder: (context, index) => Divider(
                  color: Colors.grey[300],
                  height: 0,
                  indent: 0,
                ),
            itemCount: devices.length,
            itemBuilder: (context, i) {
              Fimber.d("Build row for $i");
              return _buildRow(context, devices[i], _createTapListener(devicesBloc, devices[i]));
            });

  static DeviceTapListener _createTapListener(DevicesBloc devicesBloc, BleDevice bleDevice) {
    return () {
      Fimber.d("clicked device: ${bleDevice.name}");
      devicesBloc.devicePicker.add(bleDevice);
    };
  }

  static Widget _buildAvatar(BuildContext context, BleDevice device) {
    switch (device.category) {
      case DeviceCategory.sensorTag:
        return CircleAvatar(
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Image.asset('assets/ti_logo.png'),
            ),
            backgroundColor: Theme.of(context).accentColor);
      case DeviceCategory.hex:
        return CircleAvatar(child: CustomPaint(painter: HexPainter(), size: Size(20, 24)), backgroundColor: Colors.black);
      case DeviceCategory.other:
      default:
        return CircleAvatar(child: Icon(Icons.bluetooth), backgroundColor: Theme.of(context).primaryColor, foregroundColor: Colors.white);
    }
  }

  static Widget _buildRow(BuildContext context, BleDevice device, DeviceTapListener deviceTapListener) {
    return ListTile(
      leading: Padding(
        padding: const EdgeInsets.only(top: 8),
        child: _buildAvatar(context, device),
      ),
      title: Text(device.name),
      trailing: Padding(
        padding: const EdgeInsets.only(top: 16),
        child: Icon(Icons.chevron_right, color: Colors.grey),
      ),
      subtitle: Column(
        children: <Widget>[
          Text(
            device.id.toString(),
            style: TextStyle(fontSize: 10),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          )
        ],
        crossAxisAlignment: CrossAxisAlignment.start,
      ),
      onTap: deviceTapListener,
      contentPadding: EdgeInsets.fromLTRB(16, 0, 16, 12),
    );
  }
}
