# Bridge value parsing is referenced directly by platform adapter modules.
-keep public class com.sandrox.sfiora.bridge.SfioraBridgeRuntime { public *; }
-keep public interface com.sandrox.sfiora.bridge.SfioraBridgeRuntime$* { *; }
-keep public interface com.sandrox.sfiora.bridge.SfioraBridgeJsonCallback { *; }
