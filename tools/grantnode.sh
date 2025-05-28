#!/bin/bash
echo "Granting node and services required permissions..."

echo "Granting permission: cap_net_bind_service"
sudo setcap 'cap_net_bind_service=+ep' $(which node)

echo "Granting video permission for brightness"
sudo usermod -aG video caleb

echo "Granting display management permission"
xset +dpms

echo "Granted node required permissions"
echo ""

echo -e "brightnessctl needs elevated priveleges to run properly. To give it these elevated priveleges, run sudo visudo and add the following lines:\ncaleb ALL=(ALL) NOPASSWD: /usr/bin/brightnessctl"
echo ""
echo -e "User 'caleb' needs to be in the 'video' group to execute brightnessctl. Run this line of code in a new shell:\nnewgrp video"