extends RefCounted
class_name OnnxCpuPolicy
## Stub for EVERTBS net compile.

var fallback: WeightDrivenAi = WeightDrivenAi.new()
var model_bundle_hash: String = ""
var onnx_package_present: bool = false
var loaded_manifest_path: String = ""

func load_status_detail() -> Dictionary:
	return {"ready": 0, "package_present": 0}
