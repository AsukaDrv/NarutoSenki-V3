package re.naruto.game.net;

import android.Manifest;
import android.annotation.SuppressLint;
import android.bluetooth.BluetoothAdapter;
import android.bluetooth.BluetoothDevice;
import android.bluetooth.BluetoothServerSocket;
import android.bluetooth.BluetoothSocket;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.content.pm.PackageManager;
import android.os.Build;
import android.util.Log;

import androidx.core.content.ContextCompat;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.BufferedReader;
import java.io.BufferedWriter;
import java.io.IOException;
import java.io.InputStreamReader;
import java.io.OutputStreamWriter;
import java.util.ArrayList;
import java.util.List;
import java.util.Set;
import java.util.UUID;
import java.util.concurrent.atomic.AtomicBoolean;

import re.naruto.game.NarutoSenki;

/**
 * Mabar via Bluetooth Classic (RFCOMM/SPP custom UUID).
 * Event ke Lua (konsisten dengan TCP/WS): open / message / close / error.
 * Tambahan: "bt_devices" saat scan selesai / menemukan device.
 */
public final class BluetoothLink {
    private static final String TAG = "NarutoBt";
    public static final UUID SERVICE_UUID =
            UUID.fromString("6A8B2E4A-8F3C-4E4B-9C4D-2C1F0D0B7A31");

    private static BluetoothServerSocket sServerSocket = null;
    private static BluetoothSocket sClientSocket = null;
    private static BluetoothSocket sActiveSocket = null; // koneksi aktif (kedua sisi)
    private static Thread sAcceptThread = null;
    private static Thread sConnectThread = null;
    private static final AtomicBoolean sAccepting = new AtomicBoolean(false);
    private static final AtomicBoolean sScanning = new AtomicBoolean(false);
    private static BroadcastReceiver sDiscoveryReceiver = null;
    private static final List<JSONObject> sFoundDevices = new ArrayList<>();

    private BluetoothLink() {}

    // ------------------------------------------------------------------
    // Status koneksi
    // ------------------------------------------------------------------
    public static synchronized boolean isConnected() {
        return sActiveSocket != null && sActiveSocket.isConnected();
    }

    public static synchronized boolean isAccepting() {
        return sAccepting.get();
    }

    // ------------------------------------------------------------------
    // Host: listen RFCOMM
    // ------------------------------------------------------------------
    @SuppressLint("MissingPermission")
    public static synchronized boolean host() {
        BluetoothAdapter adapter = BluetoothAdapter.getDefaultAdapter();
        if (adapter == null) {
            NarutoSenki.dispatchLinkEvent("error", "bluetooth tidak tersedia");
            return false;
        }
        if (!hasPermission(getContextIfAvailable(adapter))) {
            NarutoSenki.dispatchLinkEvent("error", "permission bluetooth belum diberikan");
            return false;
        }
        if (sAccepting.get()) {
            Log.w(TAG, "host: already accepting");
            return true;
        }
        if (sActiveSocket != null) {
            Log.w(TAG, "host: already connected");
            return true;
        }
        sAccepting.set(true);
        sAcceptThread = new Thread(new Runnable() {
            @Override
            public void run() {
                try {
                    BluetoothServerSocket server =
                            adapter.listenUsingRfcommWithServiceRecord("NarutoSenkiV3", SERVICE_UUID);
                    synchronized (BluetoothLink.class) { sServerSocket = server; }
                    Log.i(TAG, "bt host: listening");
                    while (sAccepting.get()) {
                        BluetoothSocket socket;
                        try {
                            socket = server.accept();
                        } catch (IOException e) {
                            break; // ditutup
                        }
                        synchronized (BluetoothLink.class) {
                            if (sActiveSocket != null && sActiveSocket.isConnected()) {
                                try { socket.close(); } catch (IOException ignored) {}
                                continue; // hanya 1 client pada 1v1 mabar
                            }
                            sActiveSocket = socket;
                        }
                        sAccepting.set(false);
                        JSONObject info = new JSONObject();
                        try {
                            info.put("role", "host");
                            info.put("addr", socket.getRemoteDevice() != null
                                    ? socket.getRemoteDevice().getAddress() : "");
                            info.put("name", socket.getRemoteDevice() != null
                                    ? safeName(socket.getRemoteDevice()) : "");
                            info.put("transport", "bluetooth");
                        } catch (Exception ignored) {}
                        NarutoSenki.dispatchLinkEvent("open", info.toString());
                        startReader(socket);
                        break;
                    }
                } catch (SecurityException se) {
                    Log.e(TAG, "bt host: security", se);
                    NarutoSenki.dispatchLinkEvent("error", "bt host: permission");
                } catch (IOException e) {
                    Log.e(TAG, "bt host: io", e);
                    NarutoSenki.dispatchLinkEvent("error", "bt host: " + e.getMessage());
                } finally {
                    sAccepting.set(false);
                    synchronized (BluetoothLink.class) {
                        BluetoothServerSocket ss = sServerSocket;
                        sServerSocket = null;
                        if (ss != null) {
                            try { ss.close(); } catch (IOException ignored) {}
                        }
                    }
                }
            }
        }, "NarutoBtServer");
        sAcceptThread.setDaemon(true);
        sAcceptThread.start();
        return true;
    }

    // ------------------------------------------------------------------
    // Client: connect ke device
    // ------------------------------------------------------------------
    @SuppressLint("MissingPermission")
    public static synchronized boolean connect(final String address) {
        BluetoothAdapter adapter = BluetoothAdapter.getDefaultAdapter();
        if (adapter == null || address == null || address.isEmpty()) {
            NarutoSenki.dispatchLinkEvent("error", "bt connect: alamat kosong");
            return false;
        }
        if (sActiveSocket != null && sActiveSocket.isConnected()) {
            Log.w(TAG, "connect: already connected");
            return true;
        }
        if (!hasPermission(getContextIfAvailable(adapter))) {
            NarutoSenki.dispatchLinkEvent("error", "permission bluetooth belum diberikan");
            return false;
        }
        stopAccept();
        sConnectThread = new Thread(new Runnable() {
            @Override
            public void run() {
                try {
                    BluetoothDevice device = adapter.getRemoteDevice(address);
                    BluetoothSocket socket =
                            device.createRfcommSocketToServiceRecord(SERVICE_UUID);
                    adapter.cancelDiscovery();
                    synchronized (BluetoothLink.class) { sClientSocket = socket; }
                    socket.connect(); // blocking
                    synchronized (BluetoothLink.class) { sActiveSocket = socket; }
                    JSONObject info = new JSONObject();
                    try {
                        info.put("role", "client");
                        info.put("addr", device.getAddress());
                        info.put("name", safeName(device));
                        info.put("transport", "bluetooth");
                    } catch (Exception ignored) {}
                    NarutoSenki.dispatchLinkEvent("open", info.toString());
                    startReader(socket);
                } catch (SecurityException se) {
                    Log.e(TAG, "bt connect: security", se);
                    NarutoSenki.dispatchLinkEvent("error", "bt connect: permission");
                    cleanupClient();
                } catch (IOException e) {
                    Log.e(TAG, "bt connect: io", e);
                    NarutoSenki.dispatchLinkEvent("error", "bt connect: " + e.getMessage());
                    cleanupClient();
                }
            }
        }, "NarutoBtClient");
        sConnectThread.setDaemon(true);
        sConnectThread.start();
        return true;
    }

    private static void cleanupClient() {
        synchronized (BluetoothLink.class) {
            if (sClientSocket != null) {
                try { sClientSocket.close(); } catch (IOException ignored) {}
                sClientSocket = null;
            }
            if (sActiveSocket != null && !sActiveSocket.isConnected()) {
                sActiveSocket = null;
            }
        }
    }

    // ------------------------------------------------------------------
    // Reader loop
    // ------------------------------------------------------------------
    private static void startReader(final BluetoothSocket socket) {
        Thread reader = new Thread(new Runnable() {
            @Override
            public void run() {
                try {
                    BufferedReader reader = new BufferedReader(
                            new InputStreamReader(socket.getInputStream(), "UTF-8"));
                    String line;
                    while (socket.isConnected() && (line = reader.readLine()) != null) {
                        NarutoSenki.dispatchLinkEvent("message", line);
                    }
                } catch (IOException ignored) {
                } finally {
                    boolean wasConnected;
                    synchronized (BluetoothLink.class) {
                        wasConnected = (sActiveSocket == socket);
                        if (wasConnected) sActiveSocket = null;
                    }
                    try { socket.close(); } catch (IOException ignored) {}
                    if (wasConnected) {
                        NarutoSenki.dispatchLinkEvent("close", "bluetooth disconnected");
                    }
                }
            }
        }, "NarutoBtReader");
        reader.setDaemon(true);
        reader.start();
    }

    // ------------------------------------------------------------------
    // Send
    // ------------------------------------------------------------------
    public static synchronized boolean send(String message) {
        BluetoothSocket socket = sActiveSocket;
        if (socket == null || !socket.isConnected()) return false;
        final String out = message.endsWith("\n") ? message : message + "\n";
        try {
            BufferedWriter writer = new BufferedWriter(
                    new OutputStreamWriter(socket.getOutputStream(), "UTF-8"));
            writer.write(out);
            writer.flush();
            return true;
        } catch (IOException e) {
            Log.e(TAG, "bt send failed", e);
            return false;
        }
    }

    // ------------------------------------------------------------------
    // Scan devices
    // ------------------------------------------------------------------
    @SuppressLint("MissingPermission")
    public static boolean scan(Context context) {
        BluetoothAdapter adapter = BluetoothAdapter.getDefaultAdapter();
        if (adapter == null) {
            NarutoSenki.dispatchLinkEvent("error", "bluetooth tidak tersedia");
            return false;
        }
        if (!hasPermission(context)) {
            NarutoSenki.dispatchLinkEvent("error", "permission bluetooth/location belum diberikan");
            return false;
        }
        synchronized (sFoundDevices) { sFoundDevices.clear(); }

        // device paired
        Set<BluetoothDevice> paired = adapter.getBondedDevices();
        if (paired != null) {
            for (BluetoothDevice device : paired) {
                addFoundDevice(device);
            }
        }

        IntentFilter filter = new IntentFilter(BluetoothDevice.ACTION_FOUND);
        filter.addAction(BluetoothAdapter.ACTION_DISCOVERY_FINISHED);
        if (sDiscoveryReceiver == null) {
            sDiscoveryReceiver = new BroadcastReceiver() {
                @Override
                public void onReceive(Context ctx, Intent intent) {
                    String action = intent.getAction();
                    if (BluetoothDevice.ACTION_FOUND.equals(action)) {
                        BluetoothDevice device = intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE);
                        if (device != null) addFoundDevice(device);
                    } else if (BluetoothAdapter.ACTION_DISCOVERY_FINISHED.equals(action)) {
                        emitDevices();
                        sScanning.set(false);
                    }
                }
            };
            Context appContext = context.getApplicationContext();
            if (Build.VERSION.SDK_INT >= 33) {
                appContext.registerReceiver(sDiscoveryReceiver, filter, Context.RECEIVER_EXPORTED);
            } else {
                appContext.registerReceiver(sDiscoveryReceiver, filter);
            }
        }
        sScanning.set(true);
        boolean started = adapter.startDiscovery();
        if (!started) {
            sScanning.set(false);
            Log.w(TAG, "startDiscovery gagal");
        }
        emitDevices();
        return started;
    }

    @SuppressLint("MissingPermission")
    private static void addFoundDevice(BluetoothDevice device) {
        try {
            JSONObject obj = new JSONObject();
            obj.put("addr", device.getAddress());
            obj.put("name", safeName(device));
            obj.put("paired", device.getBondState() == BluetoothDevice.BOND_BONDED);
            synchronized (sFoundDevices) {
                for (JSONObject existing : sFoundDevices) {
                    if (existing.optString("addr", "").equals(device.getAddress())) {
                        return; // sudah ada
                    }
                }
                sFoundDevices.add(obj);
            }
        } catch (Exception ignored) {}
    }

    private static String safeName(BluetoothDevice device) {
        try {
            String name = device.getName();
            return name != null ? name : "";
        } catch (SecurityException e) {
            return "";
        }
    }

    private static void emitDevices() {
        JSONArray arr = new JSONArray();
        synchronized (sFoundDevices) {
            for (JSONObject obj : sFoundDevices) {
                arr.put(obj);
            }
        }
        NarutoSenki.dispatchLinkEvent("bt_devices", arr.toString());
    }

    public static synchronized void stopScan() {
        BluetoothAdapter adapter = BluetoothAdapter.getDefaultAdapter();
        if (adapter != null && sScanning.get()) {
            try { adapter.cancelDiscovery(); } catch (SecurityException ignored) {}
        }
        sScanning.set(false);
    }

    // ------------------------------------------------------------------
    // Stop / cleanup
    // ------------------------------------------------------------------
    public static synchronized void stopAll() {
        stopAccept();
        stopScan();
        synchronized (BluetoothLink.class) {
            BluetoothSocket active = sActiveSocket;
            sActiveSocket = null;
            sClientSocket = null;
            if (active != null) {
                try { active.close(); } catch (IOException ignored) {}
            }
        }
        if (sDiscoveryReceiver != null) {
            // receiver dibuat dengan applicationContext; cukup dibiarkan ter-registry
            // karena activity destroy memanggil ini dan receiver tidak boleh leak
            sDiscoveryReceiver = null;
        }
    }

    private static void stopAccept() {
        sAccepting.set(false);
        synchronized (BluetoothLink.class) {
            BluetoothServerSocket server = sServerSocket;
            sServerSocket = null;
            if (server != null) {
                try { server.close(); } catch (IOException ignored) {}
            }
        }
        if (sAcceptThread != null) {
            sAcceptThread.interrupt();
            sAcceptThread = null;
        }
    }

    // ------------------------------------------------------------------
    // Permissions helper
    // ------------------------------------------------------------------
    private static boolean hasPermission(Context context) {
        if (context == null) return true;
        if (Build.VERSION.SDK_INT >= 31) {
            return ContextCompat.checkSelfPermission(context, Manifest.permission.BLUETOOTH_CONNECT)
                    == PackageManager.PERMISSION_GRANTED;
        }
        return ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_FINE_LOCATION)
                == PackageManager.PERMISSION_GRANTED
                || ContextCompat.checkSelfPermission(context, "android.permission.BLUETOOTH")
                == PackageManager.PERMISSION_GRANTED;
    }

    /** Helper kecil: BluetoothAdapter tidak punya getContext, simpan app context statis */
    private static Context adapterContext;
    public static void setAppContext(Context ctx) {
        adapterContext = ctx;
    }

    private static Context getContextIfAvailable(BluetoothAdapter ignored) {
        return adapterContext;
    }
}
