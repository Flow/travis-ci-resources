#!/bin/bash

function die_with() {
    echo "$*" >&2
    exit 1
}

function has_xmllint_with_xpath() {
    if [ "$(xmllint 2>&1 | grep xpath | wc -l)" = "0" ]; then
        return 1
    else
        return 0
    fi
}

function die_unless_xmllint_has_xpath() {
    has_command xmllint || die_with "Missing xmllint command, please install it (from libxml2)"
    has_xmllint_with_xpath || die_with "xmllint command is missing the --xpath option, please install the libxml2 version"
}

echo "Checking if commit is a pull request"
if [ "$TRAVIS_PULL_REQUEST" == "false" ]; then
    die_with "Skipping deployment for pull request!"
fi

echo "Getting current version from pom.xml"
if [ -z "$CURRENT_VERSION" ]; then
    has_xmllint_with_xpath
    CURRENT_VERSION=$(xmllint --xpath "/*[local-name() = 'project']/*[local-name() = 'version']/text()" pom.xml)
fi
echo "Current version from pom.xml: $CURRENT_VERSION"
RELEASE_VERSION=$(echo "$CURRENT_VERSION" | perl -pe 's/-SNAPSHOT//')
if [ "$RELEASE_VERSION" = "$CURRENT_VERSION" ]; then
    die_with "Release version requested is exactly the same as the current pom.xml version (${CURRENT_VERSION})! Is the version in pom.xml definitely a -SNAPSHOT version?"
fi

NEXT_VERSION="$(echo "$RELEASE_VERSION" | perl -pe 's{^(([0-9]+\.)+)?([0-9]+)$}{$1 . ($3 + 1)}e')"
NEXT_VERSION="$(echo "$NEXT_VERSION" | perl -pe 's/-SNAPSHOT//gi')-SNAPSHOT"
if [ "$NEXT_VERSION" = "${RELEASE_VERSION}-SNAPSHOT" ]; then
    die_with "Release version and next version are the same version!"
fi
echo "Using $RELEASE_VERSION for release"
echo "Using $NEXT_VERSION for next development version"

if [ $(git tag -l "$RELEASE_VERSION" | wc -l) != "0" ]; then
    die_with "A tag already exists ${CURRENT_VERSION} for the release version ${RELEASE_VERSION}!"
fi

echo "Updating project version and SCM information"
mvn -B release:clean release:prepare -DreleaseVersion=$RELEASE_VERSION -DdevelopementVersion=$NEXT_VERSION -DpushChanges=false -Darguments="-Dgpg.skip" -DtagNameFormat=@{project.version} || die_with "Failed to prepare release!"
sed -ri "s/"`echo $CURRENT_VERSION | sed 's/\./\\\\./g'`"/$RELEASE_VERSION/g" build.gradle || die_with "Failed to update the project version in build.gradle!"
echo "Removing commit with the development version"
git reset --hard HEAD^

echo "Squashing the merge commit into the release commit"
TARGET_COMMIT=`git rev-parse HEAD` git filter-branch -f --commit-filter 'if [ "$GIT_COMMIT" = "$TARGET_COMMIT" ]; then git_commit_non_empty_tree "$@"; else skip_commit "$@"; fi' HEAD^^..HEAD --not release/$RELEASE_VERSION

echo "Building, generating, and deploying artifacts"
mvn package javadoc:jar source:jar gpg:sign deploy --settings target/travis/settings.xml -Psigning.keyId=ED997FF2 -Psigning.password=$SIGNING_PASSWORD -Psigning.secretKeyRingFile=target/travis/maven.gpg || die_with "Failed to build/deploy artifacts!"

echo "Updating the project version in README.md"
sed -ri "s/"`echo $CURRENT_VERSION | sed 's/\./\\\\./g'`"/$RELEASE_VERSION/g" README.md || die_with "Failed to update the project version in README.MD!"

echo "Renaming the commit to skip the CI build loop"
git commit --amend -m "Release version ${RELEASE_VERSION} [ci skip]" || die_with "Failed to rename the commit"

echo "Tagging the release with git"
git tag -f "${RELEASE_VERSION}" && git push --tags || die_with "Failed to create tag ${RELEASE_VERSION}!"

echo "Force-pushing commit with git"
git push -f || die_with "Failed to push the commit!"

echo "Release cycle completed. Project is now at version ${NEXT_VERSION}. Happy developing!"
