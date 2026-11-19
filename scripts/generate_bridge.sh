#!/bin/sh
set -eu
repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$repo_dir/packages/location_bridge"
flutter pub get
dart run pigeon --input pigeons/location_api.dart
