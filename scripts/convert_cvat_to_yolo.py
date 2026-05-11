from dataclasses import dataclass
from pathlib import Path
import json
import logging
import random
import shutil
import xml.etree.ElementTree as ET

SOURCE_DIR = Path("datasets/15.인도보행영상/바운딩박스")
OUTPUT_DIR = Path("datasets/yolo_sidewalk")
MANIFEST_PATH = OUTPUT_DIR / "split_manifest.json"

VAL_RATIO = 0.2
RANDOM_SEED = 42
SPLITS = ("train", "val")

CLASSES = [
    "person",
    "car",
    "truck",
    "bus",
    "bicycle",
    "motorcycle",
    "scooter",
    "wheelchair",
    "stroller",
    "traffic_light",
    "traffic_sign",
    "pole",
    "bollard",
    "bench",
    "tree_trunk",
    "movable_signage",
    "potted_plant",
    "parking_meter",
    "stop",
    "table",
]

class_to_id = {name: i for i, name in enumerate(CLASSES)}
logger = logging.getLogger(__name__)


@dataclass(frozen=True)
class ImageItem:
    source_path: Path
    output_filename: str
    labels: list[str]


def configure_logging():
    logging.basicConfig(level=logging.INFO, format="[%(levelname)s] %(message)s")


def convert_box(width, height, xtl, ytl, xbr, ybr):
    x_center = ((xtl + xbr) / 2) / width
    y_center = ((ytl + ybr) / 2) / height
    box_width = (xbr - xtl) / width
    box_height = (ybr - ytl) / height
    return x_center, y_center, box_width, box_height


def load_manifest():
    if not MANIFEST_PATH.exists():
        return {}

    with open(MANIFEST_PATH, "r", encoding="utf-8") as f:
        manifest = json.load(f)

    return {
        filename: split
        for filename, split in manifest.get("splits", {}).items()
        if split in SPLITS
    }


def save_manifest(split_by_filename):
    MANIFEST_PATH.parent.mkdir(parents=True, exist_ok=True)
    manifest = {
        "random_seed": RANDOM_SEED,
        "val_ratio": VAL_RATIO,
        "splits": dict(sorted(split_by_filename.items())),
    }

    with open(MANIFEST_PATH, "w", encoding="utf-8") as f:
        json.dump(manifest, f, indent=2, ensure_ascii=False)
        f.write("\n")


def make_output_filename(image_path):
    return f"{image_path.parent.name}_{image_path.name}"


def label_filename(output_filename):
    return f"{Path(output_filename).stem}.txt"


def existing_split_for(output_filename):
    label_name = label_filename(output_filename)
    existing_splits = [
        split
        for split in SPLITS
        if (OUTPUT_DIR / "labels" / split / label_name).exists()
    ]

    if len(existing_splits) > 1:
        raise RuntimeError(
            f"Label for {output_filename} exists in multiple splits: {existing_splits}"
        )

    return existing_splits[0] if existing_splits else None


def deterministic_split(filename):
    rng = random.Random(f"{RANDOM_SEED}:{filename}")
    return "val" if rng.random() < VAL_RATIO else "train"


def collect_image_items():
    image_items = []
    seen_filenames = {}
    found_count = 0
    duplicate_count = 0

    for xml_path in sorted(SOURCE_DIR.rglob("*.xml")):
        folder = xml_path.parent
        tree = ET.parse(xml_path)
        root = tree.getroot()

        for image in root.findall("image"):
            image_name = image.attrib["name"]
            width = float(image.attrib["width"])
            height = float(image.attrib["height"])

            image_path = folder / image_name
            if not image_path.exists():
                logger.warning("image not found: %s", image_path)
                continue

            found_count += 1
            output_filename = make_output_filename(image_path)
            if output_filename in seen_filenames:
                duplicate_count += 1
                logger.warning(
                    "duplicate image filename skipped: %s (first: %s, duplicate: %s)",
                    output_filename,
                    seen_filenames[output_filename],
                    image_path,
                )
                continue
            seen_filenames[output_filename] = image_path

            labels = []

            for box in image.findall("box"):
                label = box.attrib["label"]

                if label not in class_to_id:
                    continue

                xtl = float(box.attrib["xtl"])
                ytl = float(box.attrib["ytl"])
                xbr = float(box.attrib["xbr"])
                ybr = float(box.attrib["ybr"])

                x_center, y_center, box_width, box_height = convert_box(
                    width, height, xtl, ytl, xbr, ybr
                )

                class_id = class_to_id[label]
                labels.append(
                    f"{class_id} {x_center:.6f} {y_center:.6f} {box_width:.6f} {box_height:.6f}"
                )

            image_items.append(ImageItem(image_path, output_filename, labels))

    return image_items, found_count, duplicate_count


def assign_splits(image_items):
    existing_manifest = load_manifest()
    split_by_filename = {}

    for item in sorted(image_items, key=lambda item: item.output_filename):
        filename = item.output_filename

        existing_split = existing_split_for(filename)
        split_by_filename[filename] = (
            existing_manifest.get(filename)
            or existing_manifest.get(item.source_path.name)
            or existing_split
            or deterministic_split(filename)
        )

    return split_by_filename


def ensure_output_dirs():
    for split_name in SPLITS:
        (OUTPUT_DIR / "images" / split_name).mkdir(parents=True, exist_ok=True)
        (OUTPUT_DIR / "labels" / split_name).mkdir(parents=True, exist_ok=True)


def convert_items(image_items, split_by_filename):
    skipped_count = 0
    converted_count = 0
    split_counts = {split: 0 for split in SPLITS}

    for item in image_items:
        split_name = split_by_filename[item.output_filename]
        image_out_dir = OUTPUT_DIR / "images" / split_name
        label_out_dir = OUTPUT_DIR / "labels" / split_name
        out_image_path = image_out_dir / item.output_filename
        out_label_path = label_out_dir / label_filename(item.output_filename)

        split_counts[split_name] += 1

        if out_label_path.exists():
            skipped_count += 1
            if not out_image_path.exists():
                shutil.copy2(item.source_path, out_image_path)
            continue

        if not out_image_path.exists():
            shutil.copy2(item.source_path, out_image_path)

        with open(out_label_path, "w", encoding="utf-8") as f:
            f.write("\n".join(item.labels))
            if item.labels:
                f.write("\n")

        converted_count += 1

    return skipped_count, converted_count, split_counts


def write_data_yaml():
    data_yaml = OUTPUT_DIR / "data.yaml"
    with open(data_yaml, "w", encoding="utf-8") as f:
        f.write(f"path: {OUTPUT_DIR.resolve()}\n")
        f.write("train: images/train\n")
        f.write("val: images/val\n")
        f.write("names:\n")
        for i, name in enumerate(CLASSES):
            f.write(f"  {i}: {name}\n")


def main():
    configure_logging()
    image_items, found_count, duplicate_count = collect_image_items()
    ensure_output_dirs()
    split_by_filename = assign_splits(image_items)
    skipped_count, converted_count, split_counts = convert_items(
        image_items, split_by_filename
    )
    save_manifest(split_by_filename)
    write_data_yaml()

    logger.info("Done.")
    logger.info("Total images: %s", found_count)
    logger.info("Skipped images: %s", skipped_count)
    logger.info("Newly converted images: %s", converted_count)
    logger.info("Duplicate filenames skipped: %s", duplicate_count)
    logger.info("Train: %s", split_counts["train"])
    logger.info("Val: %s", split_counts["val"])
    logger.info("Output: %s", OUTPUT_DIR)


if __name__ == "__main__":
    main()
