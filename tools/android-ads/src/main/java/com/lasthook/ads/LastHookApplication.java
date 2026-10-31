package com.lasthook.ads;

import android.app.Application;
import android.util.Log;

import io.appmetrica.analytics.AppMetrica;
import io.appmetrica.analytics.AppMetricaConfig;

/** Initializes analytics before the Godot Activity is created. */
public final class LastHookApplication extends Application {
    private static final String TAG = "LastHookApplication";

    @Override public void onCreate() {
        super.onCreate();
        try {
            AppMetricaConfig config = AppMetricaConfig
                    .newConfigBuilder(BuildConfig.APPMETRICA_API_KEY)
                    .build();
            AppMetrica.activate(this, config);
            AppMetrica.enableActivityAutoTracking(this);
            AppMetrica.reportEvent("appmetrica_application_started");
            Log.i(TAG, "AppMetrica activated from Application.onCreate");
        } catch (Throwable error) {
            Log.e(TAG, "AppMetrica activation failed", error);
        }
    }
}
