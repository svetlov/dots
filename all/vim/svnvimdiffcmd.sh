#!/usr/bin/env zsh

DIFF="${_LOCAL}/bin/vimdiff"
echo $DIFF

LEFT=${6};
RIGHT=${7};

$DIFF $LEFT $RIGHT;
