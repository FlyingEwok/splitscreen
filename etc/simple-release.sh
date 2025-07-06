#!/bin/sh
set -x
#
# simple-release.sh - Simplified release without GitHub CLI
#
# Build and publish to Modrinth only
#
set -eu

#
# Always run this in the root of the repo
#
cd $(git rev-parse --show-toplevel)

#
# Load environment variables if .env exists
#
if [ -f .env ]; then
    export $(cat .env | grep -v '^#' | xargs)
fi

#
# Preflight checks
#

git --version
./gradlew --version

if [ -z "${MODRINTH_TOKEN:-}" ]; then
    echo "Set MODRINTH_TOKEN in .env file or environment"
    exit 1
fi

if [ -n "$(git status --porcelain)" ]; then
  echo "Working directory not clean, cannot release"
  exit 1
fi

CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
if [ "${CURRENT_BRANCH}" != 'main' ]; then
  echo "Releases must be performed on main. Currently on '${CURRENT_BRANCH}'"
  exit 1
fi

#
# Build release
#

BUILD_LIBS_DIR='build/libs'

CURRENT_VERSION=$(sed -rn 's/^mod_version.*=[ ]*([^\n]+)$/\1/p' gradle.properties)
echo "Current version is '$CURRENT_VERSION'"

RELEASE_VERSION=$(echo $CURRENT_VERSION | sed s/-prerelease//)
if [ $CURRENT_VERSION = $RELEASE_VERSION ]; then
    echo "ERROR - current version is not a prerelease: $CURRENT_VERSION"
    exit 1
fi
echo "Release version will be '$RELEASE_VERSION'"
sed "s/^mod_version =.*/mod_version = $RELEASE_VERSION/" gradle.properties > gradle.properties.temp
rm gradle.properties
mv gradle.properties.temp gradle.properties

rm -rf "${BUILD_LIBS_DIR}"

./gradlew remapJar

git commit -am "*** Release ${RELEASE_VERSION} ***"
git push

echo "Built release ${RELEASE_VERSION}"
echo "Files ready in ${BUILD_LIBS_DIR}/"
ls -la "${BUILD_LIBS_DIR}/"

#
# Publish to modrinth
#
echo "Publishing to Modrinth..."
./gradlew modrinth

echo "Successfully published ${RELEASE_VERSION} to Modrinth!"
echo "Your mod is now available at: https://modrinth.com/mod/tPDTaOq8"

#
# Bump version number and prepare for next release
#

RELEASE_VERSION=$(sed -rn 's/^mod_version.*=[ ]*([^\n]+)$/\1/p' gradle.properties)
echo "Previous released version is '$RELEASE_VERSION'"

BUILD_METADATA=$(echo ${RELEASE_VERSION} | awk '{split($NF,v,/[+]/); $NF=v[2]}1')
BUILD_METADATA="${BUILD_METADATA}-prerelease"
NEXT_MOD_VERSION=$(echo ${RELEASE_VERSION} | awk '{split($NF,v,/[.]/); $NF=v[1]"."v[2]"."++v[3]}1')

NEXT_VERSION="${NEXT_MOD_VERSION}+${BUILD_METADATA}"
echo "Next version is ${NEXT_VERSION}"

sed "s/^mod_version =.*/mod_version = $NEXT_VERSION/" gradle.properties > gradle.properties.temp
rm gradle.properties
mv gradle.properties.temp gradle.properties

git commit -am "Prepare for next version ${NEXT_VERSION}"
git push

echo "Release complete! 🎉"
