#!/bin/bash

function die_with() { echo "$*" >&2; exit 1; }

function has_xmllint_with_xpath() { if [ "$(xmllint 2>&1 | grep xpath | wc -l)" = "0" ]; then return 1; else return 0; fi; }

function die_unless_xmllint_has_xpath() {
    has_command xmllint || die_with "Missing xmllint command, please install it (from libxml2)"
    has_xmllint_with_xpath || die_with "xmllint command is missing the --xpath option, please install the libxml2 version"
}

echo "Checking if commit is a pull request"
if [ $TRAVIS_PULL_REQUEST == true ]; then die_with "Skipping deployment for pull request!"; fi

echo "Checking if commit is from develop branch"
if [ $TRAVIS_BRANCH == develop ]; then
    echo "Deploying Javadoc and source JARs"
    mvn javadoc:jar source:jar deploy --settings $HOME/build/flow/travis/settings.xml;
    die_with "Skipping release for develop branch!";
fi

echo "Configuring git credentials"
git config --global user.email "travis@travis-ci.org" && git config --global user.name "Travis" || die_with "Failed to configure git credentials!"

echo "Getting current version from pom.xml"
if [ -z $CURRENT_VERSION ]; then
    has_xmllint_with_xpath;
    CURRENT_VERSION=$(xmllint --xpath "/*[local-name() = 'project']/*[local-name() = 'version']/text()" pom.xml);
fi

echo "Current version from pom.xml: $CURRENT_VERSION"
RELEASE_VERSION=$(echo $CURRENT_VERSION | perl -pe 's/-SNAPSHOT//')

echo "Building, generating, and deploying artifacts"
mvn package -DbuildNumber=$TRAVIS_BUILD_NUMBER -DciSystem=travis -Dcommit=${TRAVIS_COMMIT:0:7} site javadoc:jar source:jar gpg:sign deploy --settings $HOME/build/flow/travis/settings.xml -Dgpg.passphrase=$SIGNING_PASSWORD -Dgpg.publicKeyring=$HOME/build/flow/travis/pubring.gpg -Dgpg.secretKeyring=$HOME/build/flow/travis/secring.gpg -Dtag=$RELEASE_VERSION || die_with "Failed to build/deploy artifacts!"

echo "Checking for existing GitHub tags"
git fetch --tags && if [ $(git tag -l $RELEASE_VERSION | wc -l) != "0" ]; then
    die_with "A tag already exists for the version $RELEASE_VERSION!";
fi

echo "Tagging the release with git"
git fetch origin refs/heads/release/$RELEASE_VERSION:refs/heads/release/$RELEASE_VERSION
git tag -f $RELEASE_VERSION && git push -q --tags https://$GITHUB_TOKEN@github.com/$TRAVIS_REPO_SLUG.git || die_with "Failed to create tag $RELEASE_VERSION!"
echo $RELEASE_VERSION > $TRAVIS_BUILD_DIR/version.txt

echo "Release cycle completed. Happy developing!"
