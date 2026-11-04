# SOLID

Native macOS storage cleaner. Scan, review, delete. Local only.

## Install

```bash
git clone https://github.com/kaanklcrsln/Solid.git && cd Solid
./scripts/build.sh
open dist/SOLID.app
```

Requires macOS 13+ and Xcode Command Line Tools (`xcode-select --install`).

Grant Full Disk Access to SOLID for complete results.

## Safety

- Scans are read-only.
- Nothing is deleted without confirmation.
- System, protected and in-use files are blocked.
