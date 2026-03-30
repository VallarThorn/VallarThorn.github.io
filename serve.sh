#!/bin/bash
set -e

cd "$(dirname "$0")"

#bundle config set path 'vendor/bundle' > /dev/null
#bundle install --quiet
bundle exec jekyll serve
