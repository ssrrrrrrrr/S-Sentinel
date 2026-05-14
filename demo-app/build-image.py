import json
import hashlib
import tarfile
import os
import sys
import shutil

if len(sys.argv) != 5:
    print("usage: python3 build-image.py <tag> <VERSION> <FAULT_RATE> <LATENCY_MS>")
    sys.exit(1)

tag = sys.argv[1]
version = sys.argv[2]
fault_rate = sys.argv[3]
latency_ms = sys.argv[4]

image_name = "demo-app"
workdir = f"image-build-{tag}"
rootfs = f"{workdir}/rootfs"
layer_path = f"{workdir}/layer.tar"

if os.path.exists(workdir):
    shutil.rmtree(workdir)

os.makedirs(rootfs)

shutil.copy("demo-app", f"{rootfs}/demo-app")
os.chmod(f"{rootfs}/demo-app", 0o755)

with tarfile.open(layer_path, "w") as tar:
    tar.add(f"{rootfs}/demo-app", arcname="demo-app")

def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()

layer_diff_id = sha256_file(layer_path)

config = {
    "created": "2026-05-13T00:00:00Z",
    "architecture": "amd64",
    "os": "linux",
    "config": {
        "ExposedPorts": {"8080/tcp": {}},
        "Env": [
            f"VERSION={version}",
            f"FAULT_RATE={fault_rate}",
            f"LATENCY_MS={latency_ms}"
        ],
        "Entrypoint": ["/demo-app"]
    },
    "rootfs": {
        "type": "layers",
        "diff_ids": [f"sha256:{layer_diff_id}"]
    },
    "history": [
        {
            "created": "2026-05-13T00:00:00Z",
            "created_by": "manual build from scratch"
        }
    ]
}

config_json = json.dumps(config, indent=2).encode()
config_digest = hashlib.sha256(config_json).hexdigest()
config_file = f"{config_digest}.json"

with open(f"{workdir}/{config_file}", "wb") as f:
    f.write(config_json)

manifest = [
    {
        "Config": config_file,
        "RepoTags": [f"{image_name}:{tag}"],
        "Layers": ["layer.tar"]
    }
]

with open(f"{workdir}/manifest.json", "w") as f:
    json.dump(manifest, f, indent=2)

tar_name = f"{image_name}-{tag}.tar"

with tarfile.open(tar_name, "w") as tar:
    tar.add(f"{workdir}/manifest.json", arcname="manifest.json")
    tar.add(f"{workdir}/{config_file}", arcname=config_file)
    tar.add(layer_path, arcname="layer.tar")

print(f"created {tar_name}")
print(f"image tag: {image_name}:{tag}")
