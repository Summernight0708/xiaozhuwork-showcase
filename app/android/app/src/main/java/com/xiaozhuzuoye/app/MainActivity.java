package com.xiaozhuzuoye.app;

import android.os.Bundle;
import com.getcapacitor.BridgeActivity;

public class MainActivity extends BridgeActivity {
    @Override
    public void onCreate(Bundle savedInstanceState) {
        registerPlugin(XiaozhuDownloadPlugin.class);
        super.onCreate(savedInstanceState);
    }
}
