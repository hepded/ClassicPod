import argparse
from pathlib import Path
import zipfile


def main():
    parser = argparse.ArgumentParser(description="Package reviewed sources without build files or Git history.")
    parser.add_argument("destination", type=Path)
    arguments = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    destination = arguments.destination.resolve()
    directories = {".github", "ClassicPod.xcodeproj", "Sources", "Support", "Tests", "Checks", "scripts", "docs"}
    files = {".gitignore", ".gitattributes", "Package.swift", "README.md", "ASSETS.md", "VALIDATION.md", "LICENSE", "CONTRIBUTING.md", "PRIVACY.md", "SECURITY.md", "CHANGELOG.md"}
    excluded = {".git", ".build", ".swiftpm", ".idea", ".vscode", "dist", "DerivedData", "xcuserdata", "__pycache__"}
    suffixes = {".swift", ".json", ".plist", ".strings", ".entitlements", ".pbxproj", ".xcscheme", ".sh", ".py", ".md", ".yml", ".yaml", ".png", ".gif", ".icns"}
    private_names = {"library.json", "tokens.json", "credentials.json"}
    selected = []
    for path in sorted(root.rglob("*")):
        relative = path.relative_to(root)
        if any(part in excluded for part in relative.parts):
            continue
        if relative.parts[0] not in directories and relative.as_posix() not in files:
            continue
        if path.is_symlink():
            raise SystemExit(f"Refusing symbolic link: {relative}")
        if not path.is_file():
            continue
        if path.name in private_names or path.name.startswith(".env"):
            raise SystemExit(f"Refusing private configuration: {relative}")
        if relative.as_posix() not in files and path.suffix not in suffixes:
            continue
        if path.resolve() == destination:
            raise SystemExit("Destination overlaps packaged sources")
        selected.append((path, relative))
    for required in files:
        if not (root / required).is_file():
            raise SystemExit(f"Missing required file: {required}")
    destination.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(destination, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        for path, relative in selected:
            archive.write(path, str(Path("ClassicPod") / relative))
    print(f"Packaged {len(selected)} files. Review before publication; this is not a secret scanner.")


if __name__ == "__main__":
    main()
