#!/bin/bash

echo "--- Gespeicherte WLAN-Verbindungen ---"

# Listet nur WiFi-Verbindungen auf und nummeriert sie
mapfile -t connections < <(nmcli -t -f name,type connection show | grep ":802-11-wireless$" | cut -d: -f1)

if [ ${#connections[@]} -eq 0 ]; then
    echo "Keine gespeicherten WLAN-Netzwerke gefunden."
    exit 0
fi

for i in "${!connections[@]}"; do
    echo "$((i+1))) ${connections[$i]}"
done

echo "--------------------------------------"
read -p "Welche Nummer soll gelöscht werden? (oder 'q' zum Abbrechen): " choice

if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -le "${#connections[@]}" ] && [ "$choice" -gt 0 ]; then
    target="${connections[$((choice-1))]}"
    echo "Lösche Verbindung: $target..."
    sudo nmcli connection delete "$target"
    echo "Erledigt."
else
    echo "Abgebrochen oder ungültige Eingabe."
fi
