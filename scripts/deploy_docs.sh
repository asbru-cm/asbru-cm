#!/usr/bin/env bash
GH_REPO="@github.com/asbru-cm-docs/asbrucm-docs.github.io.git"
FULL_REPO="https://${GITHUB_API_KEY}$GH_REPO"

if [ "$EXECUTE_BUILD_DOCS" != "true" ] || [ "$TRAVIS_BRANCH" != "master" ] || [ -z "$CHANGELOG_GITHUB_TOKEN" ]; then
    echo "Doc build skipped"
    exit 0
fi

mkdir -p out
cd out

git init
git remote add origin "$FULL_REPO"
git fetch
git config user.name "asbrucm-docs"
git config user.email "travis@asbru-cm.net"
git checkout master

cd ../

gem install rack -v 1.6.4
gem install github_changelog_generator
github_changelog_generator --token ${GITHUB_API_KEY} --release-branch master --user asbru-cm --project asbru-cm --output doc/General/Changelog.md

mkdocs build --clean
	
build_result=$?

# Only deploy after merging to master
if [ "$build_result" == "0" ] && [ "$TRAVIS_PULL_REQUEST" == "false" ] && [ "$TRAVIS_BRANCH" == "master" ]; then

    cd out/
    touch .
    git add -A .
    git commit -m "GH-Pages update by travis after $TRAVIS_COMMIT"
    git push -q origin master
else
    exit ${build_result}  # return doc build result
fi
