package re.naruto.game.net;

import android.net.wifi.WifiManager;
import android.net.wifi.WifiManager.LocalOnlyHotspotCallback;
import android.net.wifi.WifiManager.LocalOnlyHotspotReservation;
import android.net.wifi.SoftApConfiguration;
import android.net.wifi.WifiConfiguration;
import android.os.Build;
import android.content.Context;
import android.util.Log;

import org.json.JSONObject;

import re.naruto.game.NarutoSenki;

/**
 * LocalOnlyHotspot untuk mabar tanpa router (Android 8 / API 26+).
 *
 * CATATAN API: sejak compileSdk 33, overload startLocalOnlyHotspot(WifiConfiguration,...)
 * DIHAPUS dari SDK publik — hanya tersedia startLocalOnlyHotspot(callback, handler)
 * (SSID/password ditentukan sistem) dan versi SoftApConfiguration yang @SystemApi.
 * Jadi: start tanpa config, lalu baca SSID/pass asli dari reservation:
 *   - API 33+ : reservation.getSoftApConfiguration()
 *   - API 27..32 : reservation.getWifiConfiguration()
 *
 * Event ke Lua:
 *   "hotspot_started" : {"ssid","pass","ip"}
 *   "hotspot_error"   : {"reason"}
 */
public final class HotspotManager {
    private static final String TAG = "NarutoHotspot";
    private static LocalOnlyHotspotReservation sReservation = null;
    private static volatile boolean sStarting = false;

    private HotspotManager() {}

    @SuppressWarnings("deprecation")
    public static synchronized boolean start(final Context context) {
        if (sReservation != null) {
            Log.w(TAG, "hotspot already running");
            return true;
        }
        if (Build.VERSION.SDK_INT < 26) {
            NarutoSenki.dispatchLinkEvent("hotspot_error", "LocalOnlyHotspot butuh Android 8.0+ (API 26)");
            return false;
        }
        WifiManager wifiManager = (WifiManager) context.getApplicationContext().getSystemService(Context.WIFI_SERVICE);
        if (wifiManager == null) {
            NarutoSenki.dispatchLinkEvent("hotspot_error", "WifiManager unavailable");
            return false;
        }
        sStarting = true;

        try {
            wifiManager.startLocalOnlyHotspot(new LocalOnlyHotspotCallback() {
                @Override
                public void onStarted(LocalOnlyHotspotReservation reservation) {
                    sStarting = false;
                    sReservation = reservation;
                    String ssid = "";
                    String pass = "";
                    try {
                        if (Build.VERSION.SDK_INT >= 33) {
                            SoftApConfiguration ap = reservation.getSoftApConfiguration();
                            ssid = ap.getSsid() != null ? ap.getSsid() : "";
                            CharSequence passphrase = ap.getPassphrase();
                            pass = passphrase != null ? passphrase.toString() : "";
                        } else if (Build.VERSION.SDK_INT >= 27) {
                            WifiConfiguration wc = reservation.getWifiConfiguration();
                            if (wc != null) {
                                ssid = wc.SSID != null ? wc.SSID : "";
                                // SSID dari WifiConfiguration biasanya dibungkus tanda kutip
                                if (ssid.startsWith("\"") && ssid.endsWith("\"") && ssid.length() >= 2) {
                                    ssid = ssid.substring(1, ssid.length() - 1);
                                }
                                pass = wc.preSharedKey != null ? wc.preSharedKey : "";
                            }
                        }
                    } catch (Throwable t) {
                        Log.w(TAG, "read ap config failed: " + t.getMessage());
                    }
                    emitStarted(context, ssid, pass);
                }

                @Override
                public void onFailed(int reason) {
                    sStarting = false;
                    sReservation = null;
                    Log.e(TAG, "hotspot failed reason=" + reason);
                    NarutoSenki.dispatchLinkEvent("hotspot_error", "start gagal (code " + reason + ")");
                }
            }, null);
            return true;
        } catch (Exception e) {
            sStarting = false;
            Log.e(TAG, "startLocalOnlyHotspot threw", e);
            NarutoSenki.dispatchLinkEvent("hotspot_error", "exception: " + e.getMessage());
            return false;
        }
    }

    private static void emitStarted(Context context, String ssid, String pass) {
        try {
            WifiManager wifiManager = (WifiManager) context.getApplicationContext()
                    .getSystemService(Context.WIFI_SERVICE);
            String ip = "";
            if (wifiManager != null) {
                int intIp = wifiManager.getDhcpInfo().serverAddress;
                if (intIp != 0) {
                    ip = String.format("%d.%d.%d.%d",
                            (intIp & 0xff), (intIp >> 8 & 0xff), (intIp >> 16 & 0xff), (intIp >> 24 & 0xff));
                }
                if (ip.isEmpty() || "0.0.0.0".equals(ip)) {
                    ip = "192.168.43.1";
                }
            }
            JSONObject obj = new JSONObject();
            obj.put("ssid", ssid != null ? ssid : "");
            obj.put("pass", pass != null ? pass : "");
            obj.put("ip", ip);
            Log.i(TAG, "hotspot started ssid=" + ssid + " ip=" + ip);
            NarutoSenki.dispatchLinkEvent("hotspot_started", obj.toString());
        } catch (Exception e) {
            NarutoSenki.dispatchLinkEvent("hotspot_error", "emit failed: " + e.getMessage());
        }
    }

    public static synchronized boolean isRunning() {
        return sReservation != null || sStarting;
    }

    public static synchronized void stop() {
        LocalOnlyHotspotReservation reservation = sReservation;
        sReservation = null;
        sStarting = false;
        if (reservation != null) {
            try {
                reservation.close();
            } catch (Exception ignored) {}
        }
    }
}
