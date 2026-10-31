package com.lasthook.ads;

import android.app.Activity;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.widget.FrameLayout;
import android.util.Log;
import com.yandex.mobile.ads.banner.*;
import com.yandex.mobile.ads.common.*;
import com.yandex.mobile.ads.interstitial.*;
import com.yandex.mobile.ads.rewarded.*;
import io.appmetrica.analytics.AppMetrica;
import io.appmetrica.analytics.AppMetricaConfig;
import org.godotengine.godot.Godot;
import org.godotengine.godot.plugin.GodotPlugin;
import org.godotengine.godot.plugin.SignalInfo;
import org.godotengine.godot.plugin.UsedByGodot;
import java.util.HashMap;
import java.util.HashSet;
import java.util.Map;
import java.util.Set;

/** All SDK work runs on Android's UI thread. Godot receives queued signals. */
public final class LastHookAds extends GodotPlugin {
    private static final String TAG = "LastHookAds";
    private boolean ready, initializing, destroyed, fullscreen;
    private String appMetricaApiKey = "";
    private boolean appMetricaActivated;
    private RewardedAdLoader rewardedLoader;
    private InterstitialAdLoader interstitialLoader;
    private RewardedAd rewarded;
    private InterstitialAd interstitial;

    public LastHookAds(Godot godot) { super(godot); }
    @Override public String getPluginName() { return "LastHookAds"; }

    @Override public Set<SignalInfo> getPluginSignals() {
        Set<SignalInfo> signals = new HashSet<>();
        for (String name : new String[]{"initialized", "rewarded_loaded", "interstitial_loaded",
                "reward_earned", "rewarded_closed", "interstitial_closed"}) {
            signals.add(new SignalInfo(name));
        }
        signals.add(new SignalInfo("ad_failed", String.class, String.class));
        signals.add(new SignalInfo("banner_height_changed", Integer.class));
        signals.add(new SignalInfo("banner_slot_height_changed", String.class, Integer.class));
        return signals;
    }

    private void ui(Runnable action) {
        Activity activity = getActivity();
        if (activity != null && !destroyed) activity.runOnUiThread(() -> {
            if (!destroyed && !activity.isFinishing()) action.run();
        });
    }
    private void failed(String kind, String message) { emitSignal("ad_failed", kind, message); }

    @UsedByGodot public void setAppMetricaApiKey(String apiKey) {
        if (apiKey != null) appMetricaApiKey = apiKey.trim();
    }

    /** Sends a custom event after AppMetrica has been activated. */
    @UsedByGodot public void reportEvent(String eventName) {
        if (eventName == null || eventName.trim().isEmpty()) return;
        ui(() -> {
            if (!appMetricaActivated) return;
            try {
                AppMetrica.reportEvent(eventName.trim());
            } catch (Throwable error) {
                failed("appmetrica_event", error.toString());
            }
        });
    }

    private void activateAppMetrica() {
        if (appMetricaActivated) return;
        try {
            // LastHookApplication activates AppMetrica before this plugin and
            // before the Godot Activity is created. The plugin only marks its
            // bridge ready and emits a diagnostic event here.
            appMetricaActivated = true;
            AppMetrica.reportEvent("appmetrica_plugin_initialized");
            AppMetrica.sendEventsBuffer();
            Log.i(TAG, "AppMetrica bridge ready");
        } catch (Throwable error) {
            Log.e(TAG, "AppMetrica initialization failed", error);
            failed("appmetrica_initialize", error.toString());
        }
    }

    @UsedByGodot public void initialize() {
        ui(() -> {
            if (ready) { emitSignal("initialized"); return; }
            if (initializing) return;
            initializing = true;
            try {
                activateAppMetrica();
                YandexAds.initialize(getActivity(), () -> ui(() -> {
                    try {
                        ready = true;
                        rewardedLoader = new RewardedAdLoader(getActivity());
                        interstitialLoader = new InterstitialAdLoader(getActivity());
                        emitSignal("initialized");
                    } catch (Throwable error) {
                        ready = false;
                        initializing = false;
                        failed("initialize", error.toString());
                    }
                }));
            } catch (Throwable error) {
                initializing = false;
                failed("initialize", error.toString());
            }
        });
    }

    @UsedByGodot public void loadRewarded(String id) {
        ui(() -> {
            if (!ready || fullscreen) return;
            rewardedLoader.loadAd(new AdRequest.Builder(id).build(), new RewardedAdLoadListener() {
                @Override public void onAdLoaded(RewardedAd ad) {
                    if (destroyed) return;
                    rewarded = ad;
                    emitSignal("rewarded_loaded");
                }
                @Override public void onAdFailedToLoad(AdRequestError error) {
                    if (!destroyed) failed("rewarded_load", error.getDescription());
                }
            });
        });
    }

    @UsedByGodot public void showRewarded() {
        ui(() -> {
            if (rewarded == null || fullscreen) { failed("rewarded_show", "Ad is not ready"); return; }
            fullscreen = true;
            final RewardedAd ad = rewarded;
            rewarded = null; // A loaded ad can only be shown once.
            ad.setAdEventListener(new RewardedAdEventListener() {
                private boolean earned, finished;
                @Override public void onAdShown() {}
                @Override public void onAdClicked() {}
                @Override public void onAdImpression(ImpressionData data) {}
                @Override public void onRewarded(Reward reward) {
                    if (!finished && !earned && !destroyed) {
                        earned = true;
                        emitSignal("reward_earned");
                    }
                }
                @Override public void onAdDismissed() {
                    if (finished) return;
                    finished = true;
                    ad.setAdEventListener(null);
                    fullscreen = false;
                    if (!destroyed) emitSignal("rewarded_closed");
                }
                @Override public void onAdFailedToShow(AdError error) {
                    if (finished) return;
                    finished = true;
                    ad.setAdEventListener(null);
                    fullscreen = false;
                    if (!destroyed) failed("rewarded_show", error.getDescription());
                }
            });
            ad.show(getActivity());
        });
    }

    @UsedByGodot public void loadInterstitial(String id) {
        ui(() -> {
            if (!ready || fullscreen) return;
            interstitialLoader.loadAd(new AdRequest.Builder(id).build(), new InterstitialAdLoadListener() {
                @Override public void onAdLoaded(InterstitialAd ad) {
                    if (destroyed) return;
                    interstitial = ad;
                    emitSignal("interstitial_loaded");
                }
                @Override public void onAdFailedToLoad(AdRequestError error) {
                    if (!destroyed) failed("interstitial_load", error.getDescription());
                }
            });
        });
    }

    @UsedByGodot public void showInterstitial() {
        ui(() -> {
            if (interstitial == null || fullscreen) { failed("interstitial_show", "Ad is not ready"); return; }
            fullscreen = true;
            final InterstitialAd ad = interstitial;
            interstitial = null;
            ad.setAdEventListener(new InterstitialAdEventListener() {
                private boolean finished;
                @Override public void onAdShown() {}
                @Override public void onAdClicked() {}
                @Override public void onAdImpression(ImpressionData data) {}
                @Override public void onAdDismissed() {
                    if (finished) return;
                    finished = true;
                    ad.setAdEventListener(null);
                    fullscreen = false;
                    if (!destroyed) emitSignal("interstitial_closed");
                }
                @Override public void onAdFailedToShow(AdError error) {
                    if (finished) return;
                    finished = true;
                    ad.setAdEventListener(null);
                    fullscreen = false;
                    if (!destroyed) failed("interstitial_show", error.getDescription());
                }
            });
            ad.show(getActivity());
        });
    }

    /** One banner placement: the menu banner or the gameplay banner. */
    private static final class BannerSlot {
        BannerAdView banner;
        FrameLayout container;
        BannerAdSize size;
        // Height of the loaded banner in pixels; 0 while nothing is loaded.
        int loadedHeight;
        boolean wanted;
    }
    private final Map<String, BannerSlot> slots = new HashMap<>();

    private BannerSlot slot(String name) {
        BannerSlot result = slots.get(name);
        if (result == null) {
            result = new BannerSlot();
            slots.put(name, result);
        }
        return result;
    }

    private void emitHeight(String name, int height) {
        emitSignal("banner_slot_height_changed", name, height);
        if ("menu".equals(name)) emitSignal("banner_height_changed", height);
    }

    // The menu banner keeps its original entry points.
    @UsedByGodot public void setBannerVisible(boolean visible) { setBannerSlotVisible("menu", visible); }
    @UsedByGodot public void loadBanner(String id) { loadBannerSlot("menu", id); }

    @UsedByGodot public void setBannerSlotVisible(String name, boolean visible) {
        ui(() -> {
            BannerSlot slot = slot(name);
            slot.wanted = visible;
            if (slot.container != null) {
                // INVISIBLE, never GONE: a GONE view is not measured, so a
                // banner that loaded while hidden reported no height.
                slot.container.setVisibility(visible && slot.loadedHeight > 0 ? View.VISIBLE : View.INVISIBLE);
                if (visible) slot.container.bringToFront();
            }
            // The screen lays itself out below the banner each time it shows.
            if (visible && slot.loadedHeight > 0) emitHeight(name, slot.loadedHeight);
        });
    }

    @UsedByGodot public void loadBannerSlot(String name, String id) {
        ui(() -> {
            if (!ready) return;
            destroyBanner(name);
            final BannerSlot slot = slot(name);
            Activity activity = getActivity();
            ViewGroup parent = (ViewGroup) activity.getWindow().getDecorView();
            int widthPixels = parent.getWidth();
            if (widthPixels <= 0) widthPixels = activity.getResources().getDisplayMetrics().widthPixels;
            float density = activity.getResources().getDisplayMetrics().density;
            if (density <= 0f) density = 1f;
            int widthDp = Math.round(widthPixels / density);
            // Both placements share one height rule, so they are the same size.
            int maxBannerHeightDp = widthDp > 728 ? 90 : 55;
            BannerAdSize size = BannerAdSize.inline(activity, widthDp, maxBannerHeightDp);
            slot.size = size;
            slot.loadedHeight = 0;
            slot.banner = new BannerAdView(activity);
            slot.banner.setAdSize(size);
            slot.container = new FrameLayout(activity);
            FrameLayout.LayoutParams params = new FrameLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT, size.getHeightInPixels(activity));
            // Banners belong to the top safe area, clear of the bottom
            // navigation and the thumb zone.
            params.gravity = Gravity.TOP;
            parent.addView(slot.container, params);
            // Godot's render surface can be a SurfaceView/TextureView. Keep the
            // banner in the decor overlay and explicitly raise it after every
            // load so it cannot end up behind the game surface.
            slot.container.setElevation(1000f);
            slot.container.setTranslationZ(1000f);
            slot.container.setClipChildren(false);
            FrameLayout.LayoutParams childParams = new FrameLayout.LayoutParams(
                    size.getWidthInPixels(activity), size.getHeightInPixels(activity), Gravity.CENTER);
            slot.container.addView(slot.banner, childParams);
            // Hidden while loading, but laid out (INVISIBLE, not GONE), so the
            // loaded banner can be measured. The screen moves only once it is.
            slot.container.setVisibility(View.INVISIBLE);
            final BannerAdView banner = slot.banner;
            banner.setBannerAdEventListener(new BannerAdEventListener() {
                @Override public void onAdLoaded() {
                    measureBanner(name, banner, 0);
                }
                @Override public void onAdClicked() {}
                @Override public void onImpression(ImpressionData data) {}
                @Override public void onAdFailedToLoad(AdRequestError error) {
                    if (destroyed || slot.banner != banner) return;
                    slot.loadedHeight = 0;
                    if (slot.container != null) slot.container.setVisibility(View.INVISIBLE);
                    failed("menu".equals(name) ? "banner_load" : "banner" + name + "_load", error.getDescription());
                }
            });
            banner.loadAd(new AdRequest.Builder(id).build());
        });
    }

    /** onAdLoaded can arrive before Android has measured the inline slot. */
    private void measureBanner(final String name, final BannerAdView banner, final int attempt) {
        ui(() -> {
            BannerSlot slot = slot(name);
            if (destroyed || slot.banner != banner || slot.container == null) return;
            int measured = banner.getHeight();
            if (measured <= 0 && attempt < 8) {
                slot.container.postDelayed(() -> measureBanner(name, banner, attempt + 1), 50L);
                return;
            }
            // Never give up silently: fall back to the size the slot was made for.
            if (measured <= 0 && slot.size != null) measured = slot.size.getHeightInPixels(getActivity());
            if (measured <= 0) return;
            slot.loadedHeight = measured;
            ViewGroup.LayoutParams lp = slot.container.getLayoutParams();
            if (lp != null && lp.height != measured) {
                lp.height = measured;
                slot.container.setLayoutParams(lp);
            }
            slot.container.setVisibility(slot.wanted ? View.VISIBLE : View.INVISIBLE);
            if (slot.wanted) slot.container.bringToFront();
            emitHeight(name, measured);
        });
    }

    private void destroyBanner(String name) {
        BannerSlot slot = slots.get(name);
        if (slot == null) return;
        slot.loadedHeight = 0;
        if (slot.banner != null) {
            slot.banner.setBannerAdEventListener(null);
            slot.banner.destroy();
            slot.banner = null;
        }
        if (slot.container != null) {
            ViewGroup parent = (ViewGroup) slot.container.getParent();
            if (parent != null) parent.removeView(slot.container);
            slot.container = null;
        }
    }

    @Override public void onMainDestroy() {
        destroyed = true;
        for (String name : slots.keySet().toArray(new String[0])) destroyBanner(name);
        if (rewardedLoader != null) rewardedLoader.cancelLoading();
        if (interstitialLoader != null) interstitialLoader.cancelLoading();
        if (rewarded != null) rewarded.setAdEventListener(null);
        if (interstitial != null) interstitial.setAdEventListener(null);
        rewarded = null;
        interstitial = null;
        super.onMainDestroy();
    }
}
