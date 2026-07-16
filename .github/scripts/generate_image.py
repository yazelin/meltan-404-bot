#!/usr/bin/env python3
"""Generate an image using HuggingFace Inference API.
Usage: python generate_image.py <prompt> [model_shortname]
Env: HF_TOKEN
Available models: flux-schnell (default), flux-dev, sdxl, sd3
"""
import sys, os, json

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
    # hf-inference 已下架多數生圖模型(HTTP 410),改走 HF router 的
    # provider 自動路由(fal-ai/together/replicate 等,同一把 token,計 HF credits)
    from huggingface_hub import InferenceClient

    client = InferenceClient(provider="auto", api_key=token)
    image = client.text_to_image(prompt, model=model_id)

    file_path = os.path.join(output_dir, "image.png")
    image.save(file_path)
    return file_path


if __name__ == "__main__":
    main()
