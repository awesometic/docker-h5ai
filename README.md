# docker-h5ai

## What is h5ai

I'd like to quote the [official website](https://larsjung.de/h5ai/).  
> h5ai is a modern file indexer for HTTP web servers with focus on your files. Directories are displayed in a appealing way and browsing them is enhanced by different views, a breadcrumb and a tree overview. Initially h5ai was an acronym for HTML5 Apache Index but now it supports other web servers too.

## What this project provided for

I hope this project would be useful for those who uses docker for building their server.  

## Features

### Core packages

I chose Alpine Linux for make it a **light-weight** service.  
And I do choose nginx-alpine as its base image for the sake of some tweaks of Nginx version.  

So this is composed of,

* Alpine Linux 3.8
* Nginx 1.15.x
* PHP 7.2.x

with,

* h5ai 0.29.0

'x' at the last of their version means that they could be upgraded by their maintainer.  

And I use supervisor to manage these processes. Especially, PHP-FPM7.  
This is the first time for me for using supervisor so I couldn't sure it is needed, but it looks just works. If you have any ideas, please let me know :)  

### All functions work

![all functions work](docs/docker-h5ai-functions.png)
h5ai supports extensional functions such as showing thumnails of audio and video, caching for better speed, etc. This image functions all of them.

## How can I use this

First of all, it assumes that you have installed Docker on your system.  
Pull the image from docker hub.

```bash
docker pull awesometic/h5ai
```

Run that image temporary. '--rm' option removes container when you terminate the interactive session.

### Basic usage

You can just dry run it out as the following commands.

```bash
docker run -it --rm \
-p 80:80 \
-v /wherever/you/share:/h5ai \
-v /wherever/you/config:/config \
-e TZ=Asia/Seoul \
awesometic/h5ai
```

If you want to run this image as a daemon, try to the followings.

```bash
docker run -d --name=h5ai \
-p 80:80 \
-v /wherever/you/share:/h5ai \
-v /wherever/you/config:/config \
-e TZ=Asia/Seoul \
awesometic/h5ai
```

If you want to login to visit h5ai websites so that prevents from accessing of anonymous users, just add an environments like the below.

```bash
docker run -it --name=h5ai \
-p 80:80 \
-v /wherever/you/share:/h5ai \
-v /wherever/you/config:/config \
-e TZ=Asia/Seoul \
-e HTPASSWD=true \
-e HTPASSWD_USER=awesometic \
awesometic/h5ai
```

Be aware of that **HTPASSWD** must be true for authenticating and that you have to run in interaction mode by adding **-it** to enter password for the new created user.

Then when the container runs, just let your browser browses:

``` http
http://localhost/
```

![Sample files from https://www.sample-videos.com/](docs/docker-h5ai-demo.png)
Then you can see the directories you shared.

## TODOs

* [x] Easy access to options.json
* [x] Access permission using htpasswd
* [ ] Support HTTPS - This image doesn't support SSL even if the generated cert files are preprared but you can apply SSL if you have external Let's Encrypt program and/or a reverse proxy server.

## License

This project comes with MIT license. Please see the [license file](LICENSE).  
