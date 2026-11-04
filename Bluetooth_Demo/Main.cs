using Godot; 
using System; 
using System.Text;
 
public partial class Main : Control 
	// Stores the BluetoothManager object provided by the GDBLE plugin.
	// This manager handles operations such as initializing Bluetooth, scanning for BLE devices, and creating BLE device connections.
{ 
	// Define BLE service UUID as a constant
	private const string ServiceUuid = "4faac1ea-1841-4c5a-a838-a384a8c4d357";
	
	// Define BLE characteristic UUID as a constant
	private const string CharacteristicUuid = "beb5483e-36e1-4688-b7f5-ea07361b26a8";
	
	// Define advertised name as a constant
	private const string DeviceName = "Haptic_Glove_ESP32";
	
	private Node _bluetoothManager; // Stores the BLE device object after a connection attempt is created.
	private RefCounted _targetDevice; // Stores the address of the BLE device that we want to connect to.
	private string _targetDeviceAddress = ""; // Called when the node enters the scene tree for the first time. 
	private Label _statusLabel; // Holds label that displays connection status.
	private Label _receivedDataLabel; // Holds label that displays the latest message from the glove.
	
	// Sets up interface labels, creates the bluetooth manager, registers its sognal callbacks, and starts the bluetooth initialization.
	public override void _Ready() 
	{ 
		// Find label in the scene tree.
		_statusLabel = GetNode<Label>("Status Label");
		//  Find the received data label in the scene tree.
		_receivedDataLabel = GetNode<Label>("Received Data Label");
		
		// Display starting connection state.
		_statusLabel.Text = "Connection Status: Not Connected";
		// Show placeholder until data arrives.
		_receivedDataLabel.Text = "Received Data: Waiting...";
		
		GD.Print("Test Demo Started"); 
		
		 // Stop here if the bluetooth manager class is unavailable.
		if (!ClassDB.ClassExists("BluetoothManager"))
		{
			_statusLabel.Text = "Connection Status: Bluetooth unavailable";
			GD.Print("BluetoothManager is unavailable.");
			return;
		}
		
		Variant managerVariant = ClassDB.Instantiate("BluetoothManager");
		_bluetoothManager = managerVariant.As<Node>();
		
		// Add manager to the scene.
		AddChild(_bluetoothManager);
		
		// Receive the result of bluetooth adapter initialization.
		_bluetoothManager.Connect("adapter_initialized", Callable.From<bool, string>(OnAdapterInitialized));
		
		// Receive information about each device found during scan.
		_bluetoothManager.Connect("device_discovered", Callable.From<Godot.Collections.Dictionary>(OnDeviceDiscovered));
		
		// Handle the end of scanning and attempt connection if the glove is found.
		_bluetoothManager.Connect("scan_stopped", Callable.From(OnScanStopped));
		
		// Begin initialization after manager callbacks are registered.
		_bluetoothManager.Call("initialize");
	}  
	 
	// Receives the bluetooth adapters initialization result and reports success or failure.
	private void OnAdapterInitialized(bool success, string error) 
	{ 
		if (success) 
		{ 
			GD.Print("Bluetooth initialized successfully!"); 
		} 
		else 
		{ 
			GD.Print("Bluetooth initialization failed: " + error); 
		} 
	} 
	 
	// Called when the scan button is pressed. Starts 10 second scan.
	private void OnScannerButtonPressed() 
	{ 
		GD.Print("Scan Button Pressed"); 
		 
		// Check that the bluetooth manager object was created. If it is missing, the function is exited without starting the scan.
		if (_bluetoothManager == null) 
		{ 
			GD.Print("BluetoothManager is not available."); 
			return; 
		} 
		
		// Clear the previously saved result so that the scan must discover the glove again.
		_targetDeviceAddress = "";
		GD.Print("Starting BLE scan..."); 
		
		// Show that program is searching for the glove.
		_statusLabel.Text = "Connection Status: Scanning...";
		
		// Scan for 10 seconds. Discovered devices are handled by OnDeviceDiscovered().
		_bluetoothManager.Call("start_scan", 10.0); 
	} 
	
	// Examines each discovered device and saves its address if the advertisedname matches the glove's configured name.
	private void OnDeviceDiscovered(Godot.Collections.Dictionary deviceInfo) 
	{	 
		if (deviceInfo.ContainsKey("name")) 
		{ 
			string deviceName = deviceInfo["name"].AsString(); 
			 
			if (deviceName == DeviceName) 
			{ 
				GD.Print("Target Device Found!"); 
				 
				if (deviceInfo.ContainsKey("address")) 
				{ 
					_targetDeviceAddress = deviceInfo["address"].AsString(); 
					GD.Print("Target address: " + _targetDeviceAddress); 
				} 
			} 
		} 
	} 
	
	// Handles the end of scanning. Connects if the glove is found or reports no device descovered.
	private void OnScanStopped() 
	{ 
		GD.Print("BLE scan finished."); 
		
		/*
		Could be useful later -- this commented out block displays all potential connections that were found while the program was scanning for the glove.
		Variant devices = _bluetoothManager.Call("get_discovered_devices"); 
		GD.Print("List of discovered devices:"); 
		GD.Print(devices); 
		 */
		
		// Connect automatically if the glove's address is found
		if (_targetDeviceAddress != "") 
		{ 
			ConnectToTargetDevice(); 
		} 
		else
		{
			GD.Print("Glove not found. Check that ESP32 is properly connected and powered.");
		}
	} 
	
	// Creates the target device object, registers callbacks, and starts connecting.
	private void ConnectToTargetDevice() 
	{ 
		// Scan for the glove's address in order to connect.
		if (_targetDeviceAddress == "") 
		{ 
			GD.Print("No target device address is available."); 
			return; 
		} 
		 
		GD.Print("Attempting to connect to: " + _targetDeviceAddress); 
		 
		// Show that connection attempt is starting.
		_statusLabel.Text = "Connection Status: Connecting...";
		
		// Request BLE device object representing this address from manager. Returned variant must be converted to RefCounted to be usable.
		Variant deviceVariant = _bluetoothManager.Call("connect_device", _targetDeviceAddress); 
		_targetDevice = deviceVariant.As<RefCounted>(); 
		 
		// Stop if device object isn't provided
		if (_targetDevice == null) 
		{ 
			GD.Print("Could not create BLE device object."); 
			return; 
		} 
		 
		// Handle successful and failed connection attempts.
		_targetDevice.Connect("connected", Callable.From(OnTargetDeviceConnected)); 
		
		_targetDevice.Connect("services_discovered", Callable.From<Godot.Collections.Array>(OnServicesDiscovered)); 
		
		// Handle bluetooth disconnection.
		_targetDevice.Connect("disconnected", Callable.From(OnTargetDeviceDisconnected));
		
		// Handle the service list returned after device discovery.
		_targetDevice.Connect("connection_failed", Callable.From<string>(OnTargetDeviceConnectionFailed)); 
		
		// Handle the result of a requested read.
		_targetDevice.Connect("characteristic_read", Callable.From<string, byte[]>(OnCharacteristicRead)); 
		
		// Handle ongoing updates after subscribing to notifications.
		_targetDevice.Connect("characteristic_notified", Callable.From<string, byte[]>(OnCharacteristicNotified));
		
		// Report failures during operation (reads, writes, subscriptions).
		_targetDevice.Connect("operation_failed", Callable.From<string, string>(OnOperationFailed));
		
		// Begin the connection attempt.
		_targetDevice.Call("connect_async"); 
	} 
	
	// Called when the bluetooth connection succeeds. Updates the status label, and requests discovery of the device's service and characteristic.
	private void OnTargetDeviceConnected() 
	{ 
		// Show connected after the connection is confirmed.
		_statusLabel.Text = "Connection Status: Connected";
		
		GD.Print("Successfully connected to " + DeviceName); 
		GD.Print("Discovering GATT services..."); 
		
		// Request the service and characteristic available on the ESP32.
		_targetDevice.Call("discover_services"); 
	} 
	
	// Reports failure of of a bluetooth connection attempt.
	private void OnTargetDeviceConnectionFailed(string error) 
	{ 
		GD.Print("Connection failed: " + error); 
	} 
	
	// Called when the program finishes discovering the connected device's services. Requests a read of the characteristic's current value.
	private void OnServicesDiscovered(Godot.Collections.Array services) 
	{ 
		GD.Print("Services Discovered!"); 
		 
		// Examine each service reported.
		foreach (Variant serviceVariant in services) 
		{ 
			// Convert the GDBLE plugin's Variant into service details.
			Godot.Collections.Dictionary service = serviceVariant.AsGodotDictionary(); 
			 
			// Skips entries that don't contain a service UUID.
			if (!service.ContainsKey("uuid"))
			{
				continue;
			}
			
			string discoveredServiceUuid = service["uuid"].AsString();
			
			// Skip services that do not match the glove's service
			if (discoveredServiceUuid != ServiceUuid)
			{
				continue;
			}
			
			GD.Print("Glove service found");
			
			// Obtain characteristic list before finding and reading data.
			if (!service.ContainsKey("characteristics"))
			{
				GD.Print("No characteristic list was provided for the glove service");
				return;
			}
			
			Godot.Collections.Array characteristics = service["characteristics"].AsGodotArray();
			
			// Examine characteristics within the matching service.
			foreach (Variant characteristicVariant in characteristics)
			{
				Godot.Collections.Dictionary characteristic = characteristicVariant.AsGodotDictionary();
				
				if (!characteristic.ContainsKey("uuid"))
				{
					continue;
				}
				
				string discoveredCharacteristicUuid = characteristic["uuid"].AsString();
				
				// Skip characteristics that do not match our data characteristic.
				if (discoveredCharacteristicUuid != CharacteristicUuid)
				{
					continue;
				}
				
				GD.Print("Glove data characteristic found. Reading...");
				
				//Request current value. Result arrives through OnCharacteristicRead().
				_targetDevice.Call("read_characteristic", ServiceUuid, CharacteristicUuid);
				
				//Target found and read requested.
				return;
			}
			
			GD.Print("Glove data characteristic was not found.");
			return;
			}
			
			GD.Print("Glove service was not found.");
	} 
	
	// Called when the GDBLE plugin returns the value requested by read_characteristic.
	private void OnCharacteristicRead(string characteristicUuid, byte[] data) 
	{ 
		// Convert received bytes into readable data.
		string message = Encoding.UTF8.GetString(data);
		GD.Print("Message from board: " + message);
		
		SendTestMessage();
		
		// Request incoming updates from the glove's characteristic. Incoming notifications are handled by OnCharacteristicRead().
		_targetDevice.Call("subscribe_characteristic", ServiceUuid, CharacteristicUuid);
		
		// Confirm request was made.
		GD.Print("Notification subscription requested");
	} 
	
	// Called when a subscribed characteristic sends a notification. characteristicUuid identifies its source, and data contains the received bytes.
	private void OnCharacteristicNotified(string characteristicUuid, byte[] data) 
	{
		// Ignore notifications from other characteristics.
		if  (characteristicUuid != CharacteristicUuid) {
			return;
		}
		
		// Convert incoming updates from bytes to text
		string message = Encoding.UTF8.GetString(data);
		
		// Replace the displayed data value with the newest incoming message.
		_receivedDataLabel.Text = "Received Data: " + message;
		
		// Display each incoming message as it arrives.
		GD.Print("Board update: " + message);
	}
	
	// Converts test greeting into bytes and requests a write to the gloves characteristic.
	private void SendTestMessage()
	{
		// Convert the message into bytes for Bluetooth transmission.
		byte[] data = Encoding.UTF8.GetBytes("Hello, from Godot!");

		// Write to the ESP32 characteristic and request acknowledgement.
		_targetDevice.Call("write_characteristic", ServiceUuid, CharacteristicUuid, data, true);

		GD.Print("Test message write requested.");
	}
	
	// Called when disconnect button is pressed. Checks for connection and requests disconect if it is.
	private void OnDisconnectButtonPressed()
	{
		// Stop if no BLE device has been created.
		if (_targetDevice == null)
		{
			GD.Print("No device is available to disconnect.");
			return;
		}
		
		// Check that the device is currently connected.
		if (!_targetDevice.Call("is_connected").AsBool())
		{
			GD.Print("The glove is not currently connected.");
			return;
		}
		
		// Request disconnection. Calls OnTargetDeviceDisconnected() to update labels.
		GD.Print("Disconnection requested.");
		_targetDevice.Call("disconnect");
	}
	
	// Handles changing of label names, confirmation that target device is disconnected.
	private void OnTargetDeviceDisconnected()
	{
		// Show that the connection has ended and the data has stopped.
		_statusLabel.Text = "Connection Status: Disconnected";
		_receivedDataLabel.Text = "Received Data: Disconnected";
		
		GD.Print("Glove Test Disconnected");
	}
	
	// Reports operation name and error when a read, write, or subscription fails.
	private void OnOperationFailed(string operation, string error)
	{
		GD.Print("BLE Operation Failed " + operation + " | " + error);
	}
}
