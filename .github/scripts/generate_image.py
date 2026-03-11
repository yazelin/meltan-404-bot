#!/usr/bin/env python3
"""Generate an image using HuggingFace Inference API.
Usage: python generate_image.py <prompt> [model_shortname]
Env: HF_TOKEN
Available models: flux-schnell (default), flux-dev, sdxl, sd3
"""
import sys, os, json, urllib.request, urllib.error

MODELS = {
    "flux-schnell": "black-forest-labs/FLUX.1-schnell",
    "flux-dev":     "black-forest-labs/FLUX.1-dev",
    "sdxl":         "stabilityai/stable-diffusion-xl-base-1.0",
    "sd3":          "stabilityai/stable-diffusion-3-medium",
}

def main():
    if len(sys.argv) < 2:
        print(json.dumps({"ok": False, "error": "Usage: generate_image.py <prompt> [model]"}))
        sys.exit(1)

    prompt = sys.argv[1]
    model_key = sys.argv[2] if len(sys.argv) > 2 else "flux-schnell"
    hf_token = os.environ.get("HF_TOKEN")

    if not hf_token:
        print(json.dumps({"ok": False, "error": "HF_TOKEN not set"}))
        sys.exit(1)

    model_id = MODELS.get(model_key)
    if not model_id:
        print(json.dumps({"ok": False, "error": f"Unknown model: {model_key}. Available: {', '.join(MODELS.keys())}"}))
        sys.exit(1)

    output_dir = "/tmp/generated-images"
    os.makedirs(output_dir, exist_ok=True)

    # Try requested model, fallback to flux-schnell if different
    models_to_try = [model_id]
    fallback = MODELS["flux-schnell"]
    if model_id != fallback:
        models_to_try.append(fallback)

    last_error = None
    for mid in models_to_try:
        try:
            file_path = generate_with_model(hf_token, mid, prompt, output_dir)
            print(json.dumps({"ok": True, "file_path": file_path, "model": mid}))
            return
        except Exception as e:
            last_error = str(e)
            print(f"Model {mid} failed: {last_error}", file=sys.stderr)

    print(json.dumps({"ok": False, "error": f"All models failed. Last: {last_error}"}))
    sys.exit(1)


def generate_with_model(token, model_id, prompt, output_dir):
    url = f"https://router.huggingface.co/hf-inference/models/{model_id}"
    payload = json.dumps({"inputs": prompt}).encode("utf-8")

    req = urllib.request.Request(
        url,
        data=payload,
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
            "Accept": "image/*",
        },
        method="POST",
    )

    try:
        with urllib.request.urlopen(req, timeout=120) as resp:
            content_type = resp.headers.get("Content-Type", "image/png")
            image_data = resp.read()
    except urllib.error.HTTPError as e:
        error_body = e.read().decode("utf-8", errors="replace")
        raise Exception(f"HTTP {e.code}: {error_body[:500]}")

    if len(image_data) < 1000:
        # Likely an error response, not an image
        try:
            err = json.loads(image_data)
            raise Exception(err.get("error", str(err)))
        except (json.JSONDecodeError, UnicodeDecodeError):
            pass

    ext = "png"
    if "jpeg" in content_type or "jpg" in content_type:
        ext = "jpg"
    elif "webp" in content_type:
        ext = "webp"

    file_path = os.path.join(output_dir, f"image.{ext}")
    with open(file_path, "wb") as f:
        f.write(image_data)
    return file_path


if __name__ == "__main__":
    main()
