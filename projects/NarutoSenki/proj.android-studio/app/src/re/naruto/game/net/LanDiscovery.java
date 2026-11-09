package re.naruto.game.net;

import android.annotation.SuppressLint;
import android.util.Log;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.IOException;
import java.net.DatagramPacket;
import java.net.DatagramSocket;
import java.net.InetAddress;
import java.net.InterfaceAddress;
import java.net.NetworkInterface;
import java.net.SocketTimeoutException;
import java.util.Collections;
import java.util.List;
import java.util.concurrent.atomic.AtomicBoolean;

import re.naruto.game.NarutoSenki;

/**
 * Service discovery untuk mabar WiFi LAN:
 *  - Host   : mengirim beacon JSON tiap 1 detik ke broadcast + multicast (UDP 9112).
 *  - Client : mendengarkan beacon, mengumpulkan room, mengeluarkan event "lan_rooms".
 *
 * Format beacon: {"name","port","host_ip","players","max","game":"ns3"}
 */
public final class LanDiscovery {
    private static final String TAG = "NarutoLan";
    public static final int BEACON_PORT = 9112;
    private static final String MULTICAST_ADDR = "239.255.0.1";
    private static final long ROOM_TTL_MS = 8000;

    private static final AtomicBoolean sRunning = new AtomicBoolean(false);
    private static DatagramSocket sSocket = null;
    private static Thread sThread = null;
    // Client side cache
    private static final java.util.LinkedHashMap<String, JSONObject> sRooms =
            new java.util.LinkedHashMap<>();
    private static volatile boolean sDirty = false;
    private static volatile boolean sClientScanning = false;

    private LanDiscovery() {}

    // ------------------------------------------------------------------
    // Host: broadcast beacon
    // ------------------------------------------------------------------
    public static synchronized boolean startHosting(String roomName, int gamePort, int players, int max) {
        if (sRunning.get()) stopAll();
        final String name = (roomName == null || roomName.isEmpty()) ? "Naruto Room" : roomName;
        final int port = gamePort > 0 ? gamePort : TcpLink.DEFAULT_PORT;
        final int playerCount = Math.max(1, players);
        final int maxCount = Math.max(2, max);
        sRunning.set(true);
        sThread = new Thread(new Runnable() {
            @Override
            public void run() {
                DatagramSocket socket = null;
                try {
                    socket = new DatagramSocket();
                    socket.setBroadcast(true);
                    synchronized (LanDiscovery.class) { sSocket = socket; }
                    final byte[] payload = buildBeacon(name, port, TcpLink.getLocalIpAddress(),
                            playerCount, maxCount).getBytes("UTF-8");
                    Log.i(TAG, "hosting beacon started: " + name + " port=" + port);
                    while (sRunning.get() && !socket.isClosed()) {
                        try {
                            List<NetworkInterface> nis = Collections.list(NetworkInterface.getNetworkInterfaces());
                            for (NetworkInterface ni : nis) {
                                if (!ni.isUp() || ni.isLoopback()) continue;
                                for (InterfaceAddress ia : ni.getInterfaceAddresses()) {
                                    InetAddress bcast = ia.getBroadcast();
                                    if (bcast == null) continue;
                                    try {
                                        socket.send(new DatagramPacket(payload, payload.length, bcast, BEACON_PORT));
                                    } catch (IOException ignored) {}
                                }
                            }
                            // multicast juga
                            try {
                                InetAddress group = InetAddress.getByName(MULTICAST_ADDR);
                                socket.send(new DatagramPacket(payload, payload.length, group, BEACON_PORT));
                            } catch (IOException ignored) {}
                        } catch (Exception e) {
                            Log.w(TAG, "beacon send error: " + e.getMessage());
                        }
                        try { Thread.sleep(1000); } catch (InterruptedException e) { break; }
                    }
                } catch (IOException e) {
                    Log.e(TAG, "startHosting failed", e);
                    NarutoSenki.dispatchLinkEvent("error", "lan beacon: " + e.getMessage());
                } finally {
                    if (socket != null && !socket.isClosed()) socket.close();
                    synchronized (LanDiscovery.class) { sSocket = null; }
                }
            }
        }, "NarutoLanBeacon");
        sThread.setDaemon(true);
        sThread.start();
        return true;
    }

    private static String buildBeacon(String name, int port, String hostIp, int players, int max) {
        JSONObject obj = new JSONObject();
        try {
            obj.put("game", "ns3");
            obj.put("name", name);
            obj.put("port", port);
            obj.put("host_ip", hostIp != null ? hostIp : "");
            obj.put("players", Math.max(1, players));
            obj.put("max", Math.max(2, max));
        } catch (Exception ignored) {}
        return obj.toString();
    }

    // ------------------------------------------------------------------
    // Client: scan rooms
    // ------------------------------------------------------------------
    public static synchronized boolean startScan() {
        if (sClientScanning) return true;
        sClientScanning = true;
        sRooms.clear();
        sDirty = true;
        Thread t = new Thread(new Runnable() {
            @SuppressLint("NewApi")
            @Override
            public void run() {
                DatagramSocket socket = null;
                try {
                    socket = new DatagramSocket(null);
                    socket.setReuseAddress(true);
                    socket.bind(new java.net.InetSocketAddress(BEACON_PORT));
                    socket.setSoTimeout(500);
                    byte[] buf = new byte[1024];
                    long lastEmit = 0;
                    while (sClientScanning && !socket.isClosed()) {
                        DatagramPacket packet = new DatagramPacket(buf, buf.length);
                        try {
                            socket.receive(packet);
                        } catch (SocketTimeoutException e) {
                            emitRoomsIfDirty(lastEmit);
                            continue;
                        }
                        try {
                            String json = new String(packet.getData(), 0, packet.getLength(), "UTF-8");
                            JSONObject room = new JSONObject(json);
                            if (!"ns3".equals(room.optString("game", ""))) continue;
                            String ip = room.optString("host_ip", "");
                            if (ip.isEmpty()) ip = packet.getAddress().getHostAddress();
                            room.put("host_ip", ip);
                            room.put("last_seen", System.currentTimeMillis());
                            synchronized (sRooms) {
                                sRooms.put(ip + "|" + room.optString("name", ""), room);
                            }
                            sDirty = true;
                        } catch (Exception e) {
                            Log.w(TAG, "bad beacon ignored");
                        }
                        emitRoomsIfDirty(lastEmit);
                    }
                } catch (IOException e) {
                    Log.e(TAG, "lan scan failed", e);
                    NarutoSenki.dispatchLinkEvent("error", "lan scan: " + e.getMessage());
                } finally {
                    if (socket != null && !socket.isClosed()) socket.close();
                }
            }
        }, "NarutoLanScan");
        t.setDaemon(true);
        t.start();
        return true;
    }

    private static void emitRoomsIfDirty(long lastEmit) {
        long now = System.currentTimeMillis();
        if (!sDirty || (now - lastEmit) < 500) return;
        synchronized (sRooms) {
            // buang room kadaluarsa
            sRooms.values().removeIf(room -> now - room.optLong("last_seen", 0) > ROOM_TTL_MS);
            JSONArray arr = new JSONArray();
            for (JSONObject room : sRooms.values()) {
                arr.put(room);
            }
            NarutoSenki.dispatchLinkEvent("lan_rooms", arr.toString());
        }
        sDirty = false;
    }

    public static synchronized void stopScan() {
        sClientScanning = false;
        sRooms.clear();
    }

    // ------------------------------------------------------------------
    // Stop all
    // ------------------------------------------------------------------
    public static synchronized void stopAll() {
        sRunning.set(false);
        sClientScanning = false;
        DatagramSocket socket = sSocket;
        sSocket = null;
        if (socket != null && !socket.isClosed()) {
            socket.close();
        }
        if (sThread != null) {
            sThread.interrupt();
            sThread = null;
        }
        sRooms.clear();
    }
}
