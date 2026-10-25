package com.lasthook.ads;

import android.app.Activity;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.widget.FrameLayout;
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
import java.util.HashSet;
import java.util.Set;

/** All SDK work runs on Android's UI thread. Godot receives queued signals. */
public final class LastHookAds extends GodotPlugin {
    private boolean ready, initializing, destroyed, fullscreen, bannerWanted;
    private String appMetricaApiKey = "";
    private boolean appMetricaActivated;
    private BannerAdView banner;
    private FrameLayout bannerContainer;
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
        if (appMetricaActivated || appMetricaApiKey.isEmpty()) return;
        try {
            AppMetricaConfig config = AppMetricaConfig.newConfigBuilder(appMetricaApiKey).build();
            AppMetrica.activate(getActivity().getApplicationContext(), config);
            appMetricaActivated = true;
        } catch (Throwable error) {
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

    @UsedByGodot public void setBannerVisible(boolean visible) {
        ui(() -> {
            bannerWanted = visible;
            if (bannerContainer != null) {
                bannerContainer.setVisibility(visible ? View.VISIBLE : View.GONE);
                if (visible) bannerContainer.bringToFront();
            }
        });
    }

    @UsedByGodot public void loadBanner(String id) {
        ui(() -> {
            if (!ready) return;
            destroyBanner();
            Activity activity = getActivity();
            ViewGroup parent = (ViewGroup) activity.getWindow().getDecorView();
            int widthPixels = parent.getWidth();
            if (widthPixels <= 0) widthPixels = activity.getResources().getDisplayMetrics().widthPixels;
            float density = activity.getResources().getDisplayMetrics().density;
            if (density <= 0f) density = 1f;
            int widthDp = Math.round(widthPixels / density);
            int maxBannerHeightDp = widthDp > 728 ? 90 : 55;
            BannerAdSize size = BannerAdSize.inline(activity, widthDp, maxBannerHeightDp);
            banner = new BannerAdView(activity);
            banner.setAdSize(size);
            bannerContainer = new FrameLayout(activity);
            FrameLayout.LayoutParams params = new FrameLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT, size.getHeightInPixels(activity));
            // The main-menu banner belongs to the top safe area. Keeping it
            // outside the bottom navigation prevents a black placeholder from
            // appearing under the menu and leaves the lower bar anchored.
            params.gravity = Gravity.TOP;
            parent.addView(bannerContainer, params);
            // Godot's render surface can be a SurfaceView/TextureView. Keep the
            // banner in the decor overlay and explicitly raise it after every
            // load so it cannot end up behind the game surface.
            bannerContainer.setElevation(1000f);
            bannerContainer.setTranslationZ(1000f);
            bannerContainer.setClipChildren(false);
            FrameLayout.LayoutParams childParams = new FrameLayout.LayoutParams(
                    size.getWidthInPixels(activity), size.getHeightInPixels(activity), Gravity.CENTER);
            bannerContainer.addView(banner, childParams);
            bannerContainer.setVisibility(bannerWanted ? View.VISIBLE : View.GONE);
            if (bannerWanted) bannerContainer.bringToFront();
            emitSignal("banner_height_changed", size.getHeightInPixels(activity));
            banner.setBannerAdEventListener(new BannerAdEventListener() {
                @Override public void onAdLoaded() {
                    ui(() -> {
                        if (destroyed || banner == null || bannerContainer == null) return;
                        int measured = banner.getHeight();
                        if (measured > 0) {
                            ViewGroup.LayoutParams lp = bannerContainer.getLayoutParams();
                            if (lp != null && lp.height != measured) {
                                lp.height = measured;
                                bannerContainer.setLayoutParams(lp);
                            }
                            emitSignal("banner_height_changed", measured);
                        }
                    });
                }
                @Override public void onAdClicked() {}
                @Override public void onImpression(ImpressionData data) {}
                @Override public void onAdFailedToLoad(AdRequestError error) {
                    if (!destroyed) failed("banner_load", error.getDescription());
                }
            });
            banner.loadAd(new AdRequest.Builder(id).build());
        });
    }

    private void destroyBanner() {
        if (banner != null) {
            banner.setBannerAdEventListener(null);
            banner.destroy();
            banner = null;
        }
        if (bannerContainer != null) {
            ViewGroup parent = (ViewGroup) bannerContainer.getParent();
            if (parent != null) parent.removeView(bannerContainer);
            bannerContainer = null;
        }
    }

    @Override public void onMainDestroy() {
        destroyed = true;
        destroyBanner();
        if (rewardedLoader != null) rewardedLoader.cancelLoading();
        if (interstitialLoader != null) interstitialLoader.cancelLoading();
        if (rewarded != null) rewarded.setAdEventListener(null);
        if (interstitial != null) interstitial.setAdEventListener(null);
        rewarded = null;
        interstitial = null;
        super.onMainDestroy();
    }
}
