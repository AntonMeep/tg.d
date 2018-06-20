#!/usr/bin/env bash

dub fetch covered
dub -b unittest-cov -c unittest
dub run covered -- -a