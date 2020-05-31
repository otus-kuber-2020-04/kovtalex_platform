#!/bin/bash
helm repo add templating https://harbor.35.189.202.237.nip.io/chartrepo/library

helm push --username admin --password Harbor12345  frontend/ templating
helm push --username admin --password Harbor12345  hipster-shop/ templating
