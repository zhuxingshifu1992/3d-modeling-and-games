"""Fetch the small, curated CC0 environment texture set. Powered by Poly Haven.

Only explicit asset/map pairs are downloaded; no site crawling or paid assets.
Re-running verifies existing files rather than replacing edited assets.
"""
from pathlib import Path
import concurrent.futures
import hashlib
import json
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
DEST = ROOT / "assets" / "environment"
HEADERS = {"User-Agent": "DownhillFlow-Environment/1.0 (personal CC0 asset import; Powered by Poly Haven)"}
REQUESTS = {
    "asphalt_02": ("2k", ["Diffuse", "nor_gl", "arm"]),
    "rock_face": ("2k", ["Diffuse", "nor_gl", "arm", "Displacement"]),
    "aerial_grass_rock": ("2k", ["Diffuse", "nor_gl", "arm"]),
    "leafy_grass": ("1k", ["Diffuse", "nor_gl", "arm"]),
    "bark_willow": ("1k", ["Diffuse", "nor_gl", "arm"]),
    "tree_small_02": ("1k", ["leaves_diff", "leaves_alpha", "leaves_nor_gl"]),
    "grass_medium_01": ("1k", ["Diffuse", "Alpha"]),
    "chapmans_drive": ("2k", ["hdri"]),
    "kloofendal_48d_partly_cloudy_puresky": ("2k", ["hdri"]),
}

def fetch(url):
    with urllib.request.urlopen(urllib.request.Request(url, headers=HEADERS), timeout=90) as response:
        return response.read()

def asset_jobs(slug, resolution, maps):
    catalog = json.loads(fetch("https://api.polyhaven.com/files/" + slug))
    info = json.loads(fetch("https://api.polyhaven.com/info/" + slug))
    for channel in maps:
        options = catalog[channel][resolution]
        extension = "hdr" if channel == "hdri" else "jpg"
        if extension not in options:
            extension = "png"
        spec = options[extension]
        yield {"asset": slug, "channel": channel, "resolution": resolution,
               "page": "https://polyhaven.com/a/" + slug,
               "authors": info.get("authors", {}), "dimensions_mm": info.get("dimensions"),
               "license": "CC0-1.0", "license_url": "https://polyhaven.com/license",
               "filename": spec["url"].rsplit("/", 1)[-1], **spec}

def download(job):
    output = DEST / job["filename"]
    data = output.read_bytes() if output.exists() else fetch(job["url"])
    assert hashlib.md5(data).hexdigest() == job["md5"], f"Source integrity mismatch: {output}"
    if not output.exists():
        output.write_bytes(data)
    job["sha256"] = hashlib.sha256(data).hexdigest()
    job["local_path"] = output.relative_to(ROOT).as_posix()
    print("VERIFIED", output.name, len(data), flush=True)
    return job

if __name__ == "__main__":
    DEST.mkdir(parents=True, exist_ok=True)
    jobs = []
    for slug, (resolution, maps) in REQUESTS.items():
        jobs.extend(asset_jobs(slug, resolution, maps))
    with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:
        results = list(pool.map(download, jobs))
    manifest = {"retrieved": "2026-09-09", "credit": "Powered by Poly Haven",
                "description": "Original photographic PBR material maps and plant leaf/grass atlases; no generated replacement for photographs.",
                "assets": results}
    (DEST / "provenance.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")
    print("ENVIRONMENT_ASSETS_VERIFIED", len(results))
