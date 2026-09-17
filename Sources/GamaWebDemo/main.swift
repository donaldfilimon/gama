#if arch(wasm32)
import GamaWASM

_ = try? GamaWeb.install(app: BrowserDemo())
#else
print("gama-web-demo must be built for wasm32")
#endif
