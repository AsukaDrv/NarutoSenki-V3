package re.naruto.game.net;

import android.util.Log;

import org.json.JSONObject;

import java.io.BufferedReader;
import java.io.BufferedWriter;
import java.io.IOException;
import java.io.InputStreamReader;
import java.io.OutputStreamWriter;
import java.net.InetAddress;
import java.net.NetworkInterface;
import java.net.ServerSocket;
import java.net.Socket;
import java.net.SocketException;
import java.util.Collections;
import java.util.List;
import java.util.concurrent.CopyOnWriteArrayList;
import java.util.concurrent.atomic.AtomicBoolean;

import re.naruto.game.NarutoSenki;

/**
 * TCP server/client sederhana untuk mabar lokal (WiFi LAN & Hotspot).
 * Protokol: pesan UTF-8 dipisah newline ("newline framing").
 * Semua event dilempar ke Lua lewat NarutoSenki.dispatchLinkEvent
 * dengan nama event yang sama seperti WebSocket: open / message / close / error.
 */
public final class TcpLink {
    private static final String TAG = "NarutoTcp";
    public static final int DEFAULT_PORT = 9111;
    private static final int MAX_MESSAGE_LENGTH = 256 * 1024;
    private static final int MAX_CLIENTS = 8;

    private static ServerSocket sServerSocket = null;
    private static final CopyOnWriteArrayList<ClientConn> sServerClients = new CopyOnWriteArrayList<>();
    private static ClientConn sClientSideConn = null; // koneksi sisi client
    private static final AtomicBoolean sServerRunning = new AtomicBoolean(false);

    private TcpLink() {}

    // ------------------------------------------------------------------
    // Connection wrapper
    // ------------------------------------------------------------------
    private static final class ClientConn {
        final Socket socket;
        final BufferedWriter writer;
        final BufferedReader reader;
        final String remote;
        final AtomicBoolean closed = new AtomicBoolean(false);

        ClientConn(Socket socket) throws IOException {
            this.socket = socket;
            socket.setTcpNoDelay(true);
            this.writer = new BufferedWriter(new OutputStreamWriter(socket.getOutputStream(), "UTF-8"));
            this.reader = new BufferedReader(new InputStreamReader(socket.getInputStream(), "UTF-8"));
            InetAddress addr = socket.getInetAddress();
            this.remote = (addr != null ? addr.getHostAddress() : "unknown");
        }

        void closeQuietly() {
            if (closed.compareAndSet(false, true)) {
                try { socket.close(); } catch (IOException ignored) {}
            }
        }
    }

    // ------------------------------------------------------------------
    // Host side
    // ------------------------------------------------------------------
    public static synchronized boolean startServer(int port) {
        if (sServerRunning.get()) {
            Log.w(TAG, "startServer: server already running");
            return true;
        }
        final int usePort = port > 0 ? port : DEFAULT_PORT;
        sServerRunning.set(true);
        Thread acceptThread = new Thread(new Runnable() {
            @Override
            public void run() {
                try {
                    ServerSocket server = new ServerSocket(usePort);
                    server.setReuseAddress(true);
                    synchronized (TcpLink.class) { sServerSocket = server; }

                    JSONObject info = new JSONObject();
                    try {
                        info.put("role", "host");
                        info.put("port", usePort);
                        info.put("ip", getLocalIpAddress());
                    } catch (Exception ignored) {}
                    NarutoSenki.dispatchLinkEvent("open", info.toString());

                    while (sServerRunning.get() && !server.isClosed()) {
                        Socket client;
                        try {
                            client = server.accept();
                        } catch (SocketException se) {
                            break; // server ditutup
                        }
                        if (sServerClients.size() >= MAX_CLIENTS) {
                            try { client.close(); } catch (IOException ignored) {}
                            continue;
                        }
                        try {
                            final ClientConn conn = new ClientConn(client);
                            sServerClients.add(conn);
                            startReader(conn, true);
                            JSONObject joined = new JSONObject();
                            try {
                                joined.put("role", "host");
                                joined.put("event", "client_joined");
                                joined.put("addr", conn.remote);
                            } catch (Exception ignored) {}
                            NarutoSenki.dispatchLinkEvent("peer", joined.toString());
                        } catch (IOException e) {
                            Log.e(TAG, "accept: failed to setup client", e);
                            try { client.close(); } catch (IOException ignored) {}
                        }
                    }
                } catch (IOException e) {
                    Log.e(TAG, "startServer failed on port " + usePort, e);
                    NarutoSenki.dispatchLinkEvent("error", "tcp server: " + e.getMessage());
                } finally {
                    closeServerSockets();
                }
            }
        }, "NarutoTcpServer");
        acceptThread.setDaemon(true);
        acceptThread.start();
        return true;
    }

    // ------------------------------------------------------------------
    // Client side
    // ------------------------------------------------------------------
    public static synchronized boolean connectClient(final String host, final int port) {
        if (sClientSideConn != null) {
            Log.w(TAG, "connectClient: already connected");
            return true;
        }
        final String hostAddr = (host == null || host.trim().isEmpty()) ? "" : host.trim();
        final int usePort = port > 0 ? port : DEFAULT_PORT;
        Thread t = new Thread(new Runnable() {
            @Override
            public void run() {
                try {
                    Socket socket = new Socket(hostAddr, usePort);
                    ClientConn conn = new ClientConn(socket);
                    synchronized (TcpLink.class) { sClientSideConn = conn; }
                    JSONObject info = new JSONObject();
                    try {
                        info.put("role", "client");
                        info.put("addr", hostAddr);
                        info.put("port", usePort);
                    } catch (Exception ignored) {}
                    NarutoSenki.dispatchLinkEvent("open", info.toString());
                    startReader(conn, false);
                } catch (Exception e) {
                    Log.e(TAG, "connectClient failed " + hostAddr + ":" + usePort, e);
                    NarutoSenki.dispatchLinkEvent("error", "tcp connect: " + e.getMessage());
                }
            }
        }, "NarutoTcpClient");
        t.setDaemon(true);
        t.start();
        return true;
    }

    // ------------------------------------------------------------------
    // Reader loop
    // ------------------------------------------------------------------
    private static void startReader(final ClientConn conn, final boolean isHostSide) {
        Thread reader = new Thread(new Runnable() {
            @Override
            public void run() {
                try {
                    String line;
                    while (!conn.closed.get() && (line = conn.reader.readLine()) != null) {
                        if (line.length() > MAX_MESSAGE_LENGTH) {
                            Log.w(TAG, "message too large, dropped");
                            continue;
                        }
                        NarutoSenki.dispatchLinkEvent("message", line);
                    }
                } catch (IOException ignored) {
                    // koneksi terputus
                } finally {
                    conn.closeQuietly();
                    if (isHostSide) {
                        sServerClients.remove(conn);
                        try {
                            JSONObject left = new JSONObject();
                            left.put("role", "host");
                            left.put("event", "client_left");
                            left.put("addr", conn.remote);
                            NarutoSenki.dispatchLinkEvent("peer", left.toString());
                        } catch (Exception ignored) {}
                    } else {
                        synchronized (TcpLink.class) {
                            if (sClientSideConn == conn) sClientSideConn = null;
                        }
                        NarutoSenki.dispatchLinkEvent("close", "connection lost");
                    }
                }
            }
        }, "NarutoTcpReader");
        reader.setDaemon(true);
        reader.start();
    }

    // ------------------------------------------------------------------
    // Send
    // ------------------------------------------------------------------
    public static synchronized boolean send(String message) {
        if (message == null) return false;
        final String out = message.endsWith("\n") ? message : message + "\n";
        boolean any = false;
        synchronized (TcpLink.class) {
            if (sClientSideConn != null) {
                any = writeTo(sClientSideConn, out) || any;
            }
            for (ClientConn conn : sServerClients) {
                any = writeTo(conn, out) || any;
            }
        }
        return any;
    }

    private static boolean writeTo(ClientConn conn, String line) {
        try {
            synchronized (conn) {
                conn.writer.write(line);
                conn.writer.flush();
            }
            return true;
        } catch (IOException e) {
            conn.closeQuietly();
            sServerClients.remove(conn);
            return false;
        }
    }

    // ------------------------------------------------------------------
    // Stop / status
    // ------------------------------------------------------------------
    public static synchronized void stopAll() {
        sServerRunning.set(false);
        closeServerSockets();
        synchronized (TcpLink.class) {
            if (sClientSideConn != null) {
                sClientSideConn.closeQuietly();
                sClientSideConn = null;
            }
        }
    }

    public static synchronized boolean isActive() {
        return sServerRunning.get() || sClientSideConn != null || !sServerClients.isEmpty();
    }

    private static void closeServerSockets() {
        for (ClientConn conn : sServerClients) {
            conn.closeQuietly();
        }
        sServerClients.clear();
        ServerSocket server = sServerSocket;
        sServerSocket = null;
        if (server != null && !server.isClosed()) {
            try { server.close(); } catch (IOException ignored) {}
        }
    }

    // ------------------------------------------------------------------
    // Utils
    // ------------------------------------------------------------------
    public static String getLocalIpAddress() {
        try {
            List<NetworkInterface> interfaces = Collections.list(NetworkInterface.getNetworkInterfaces());
            String fallback = "";
            for (NetworkInterface ni : interfaces) {
                List<InetAddress> addrs = Collections.list(ni.getInetAddresses());
                for (InetAddress addr : addrs) {
                    if (!addr.isLoopbackAddress() && addr.getAddress().length == 4) {
                        String host = addr.getHostAddress();
                        if (host != null && !host.startsWith("192.168.43.")) {
                            return host; // preferensi: WiFi LAN biasa
                        } else if (fallback.isEmpty()) {
                            fallback = host; // fallback: IP hotspot (192.168.43.x)
                        }
                    }
                }
            }
            return fallback;
        } catch (Exception ignored) {}
        return "";
    }
}
