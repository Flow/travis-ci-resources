#!/bin/bash

function die_with() { echo "$*" >&2; exit 1; }

echo "Checking if commit is a pull request"
if [ $TRAVIS_PULL_REQUEST == false ]; then die_with "Skipping deployment for pull request!"; fi

echo "Changing directory to ${HOME} and configuring git"
cd "$HOME" || die_with "Failed to switch to ${HOME} directory!"
git config --global user.email "travis@travis-ci.org" && git config --global user.name "Travis" || die_with "Failed to configure git credentials!"

echo "Cloning gh-pages branch using token"
git clone --quiet --single-branch -b gh-pages https://${GITHUB_TOKEN}@github.com/${TRAVIS_REPO_SLUG}.git gh-pages >/dev/null || die_with "Failed to clone gh-pages branch!"

echo "Copying apidocs to gh-pages branch root"
cd gh-pages && rm -rf . || die_with "Failed to remove old Javadocs!"
if [ -d "${TRAVIS_BUILD_DIR}/target/apidocs" ]; then cp -Rf ${TRAVIS_BUILD_DIR}/target/apidocs/* . || die_with "Failed to copy apidocs to target directory!"; fi
if [ -d "${TRAVIS_BUILD_DIR}/target/site/apidocs" ]; then cp -Rf ${TRAVIS_BUILD_DIR}/target/site/apidocs/* . || die_with "Failed to copy apidocs to target directory"; fi

echo "Adding, committing, and pushing apidocs to gh-pages branch"
git add -f .
git commit -m "Javadocs for Travis build $TRAVIS_BUILD_NUMBER"
git push -qf origin gh-pages >/dev/null || die_with "Failed to push to git repository!"

echo "Javadocs updated successfully. Happy developing!"
