#!/usr/bin/env bash
GH_REPO="@github.com/asbru-cm-docs/asbrucm-docs.github.io.git"
FULL_REPO="https://${GITHUB_API_KEY}$GH_REPO"

if [ "$EXECUTE_BUILD_DOCS" != "true" ] || [ "$TRAVIS_BRANCH" != "master" ]; then
    echo "Doc build skipped, flag=[$EXECUTE_BUILD_DOCS], branch is [$TRAVIS_BRANCH]."
    exit 0
fi

if [ -z "$GITHUB_API_KEY" ]; then
    echo "GITHUB_API_KEY not set.  This is probably a pull request from another repository.  Doc build skipped."
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
github_changelog_generator --token ${GITHUB_API_KEY} --release-branch master --user asbru-cm --project asbru-cm --output doc/General/Changelog.md --no-unreleased

pip3 install --upgrade pip
pip3 install --user --requirement <(cat <<EOF
Click==7.0
future==0.18.2
Jinja2==2.11.1
livereload==2.6.1
lunr==0.5.6
Markdown==3.2.1
MarkupSafe==1.1.1
mkdocs==1.1
mkdocs-material==4.6.3
nltk==3.4.5
Pygments==2.5.2
pymdown-extensions==6.3
PyYAML==5.3
six==1.14.0
tornado==6.0.3
EOF
)

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
