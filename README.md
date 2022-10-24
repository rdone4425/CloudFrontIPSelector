# CloudFrontIPSelector ![github workflow](https://github.com/BruceWind/CloudFrontIPSelector/actions/workflows/run.yml/badge.svg?branch=main)
to choose the CloudFront IPs with the lowest possible connection latency.


### Background
Because AWS's DNS function is so good, users of AWS CloudFront typically report having an extremely steady experience.

On the other hand, those living in China use it often get timeout, shipments lost and high latency. As a result, some people prefer to bind to CloudFront's domain using low-latency IP addresses. I created this script to choose IPs with the lowest latency in these situations.


### How to use?

1. set up node environment.
In case people who havn't set up node. I highly recommand [nvm](https://github.com/nvm-sh/nvm) or [nvm-windows](https://github.com/coreybutler/nvm-windows.) to set up.

2. run this JS file.
```
npm install
node ./main.js
```

3. wait minites to get `result.txt` which contain best IPs will be saved in this folder.


### In addition

a. Have you tried Gcore-CDN?   I have written another IP-selector for Gcore: https://github.com/BruceWind/GcoreCDNIPSelector, you can try it.

b. I limit latency of IPs must below 80, if you want to change it, you can modify  this variable `THREASHOLD` in `main.js` . 