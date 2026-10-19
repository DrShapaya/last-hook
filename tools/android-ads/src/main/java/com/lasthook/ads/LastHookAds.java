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
import org.godotengine.godot.Godot;
import org.godotengine.godot.plugin.GodotPlugin;
import org.godotengine.godot.plugin.SignalInfo;
import org.godotengine.godot.plugin.UsedByGodot;
import java.util.HashSet;
import java.util.Set;

/** All SDK work runs on Android's UI thread. Godot receives queued signals. */
public final class LastHookAds extends GodotPlugin {
    private boolean ready, initializing, destroyed, fullscreen, bannerWanted;
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

    @UsedByGodot public void initialize() {
        ui(() -> {
            if (ready) { emitSignal("initialized"); return; }
            if (initializing) return;
            initializing = true;
            try {
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
            if (bannerContainer != null) bannerContainer.setVisibility(visible ? View.VISIBLE : View.GONE);
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
            BannerAdSize size = BannerAdSize.sticky(activity, Math.round(widthPixels / density));
            banner = new BannerAdView(activity);
            banner.setAdSize(size);
            bannerContainer = new FrameLayout(activity);
            FrameLayout.LayoutParams params = new FrameLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT, size.getHeightInPixels(activity));
            params.gravity = Gravity.BOTTOM;
            parent.addView(bannerContainer, params);
            FrameLayout.LayoutParams childParams = new FrameLayout.LayoutParams(
                    size.getWidthInPixels(activity), size.getHeightInPixels(activity), Gravity.CENTER);
            bannerContainer.addView(banner, childParams);
            bannerContainer.setVisibility(bannerWanted ? View.VISIBLE : View.GONE);
            emitSignal("banner_height_changed", size.getHeightInPixels(activity));
            banner.setBannerAdEventListener(new BannerAdEventListener() {
                @Override public void onAdLoaded() {}
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
