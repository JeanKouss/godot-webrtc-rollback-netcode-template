@echo off
wt wsl -d Ubuntu-24.04 -- bash -ic "cd programs/nakama && docker compose up"
