## Device image

Bootc is used for the Device, and a Containerfile (and its update) can be found in the [Device](/Device/Bootc/) directory. Ensure the build-args are provided via CLI flags or file before attempting the build.

You can also find a kickstart. How this image is delivered to the device is up to you. I built a kickstart, added it and my container image to an installation ISO, wrote it to a flash drive, and booted from it, however that's one of many ways to handle the deployment.

To build using an `.env` file you can run the following:  

`$ podman build --build-arg-file .env -f Containerfile1 -t quay.io/luferrar/part5:device001`

### RT patch
just follow instructions here
https://developers.redhat.com/articles/2025/03/06/how-pre-tuned-real-time-bootable-containers-work#the_tuning_process_steps