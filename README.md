# docker-h5ai

## What is h5ai?
I'd like to quote the [official website](https://larsjung.de/h5ai/).  
> h5ai is a modern file indexer for HTTP web servers with focus on your files. Directories are displayed in a appealing way and browsing them is enhanced by different views, a breadcrumb and a tree overview. Initially h5ai was an acronym for HTML5 Apache Index but now it supports other web servers too.

## What this project provided for?
I hope this project would be useful for those who uses docker for building their server.  

## Features?
### Core packages
I chose Alpine Linux for make it a **light-weight** service.  
And I do choose nginx-alpine as its base image for the sake of some tweaks of Nginx version.  

So this is composed of,
* Alpine Linux 3.8
* Nginx 1.15.x
* PHP 7.2.x
'x' at the last of their version means that they could be upgraded by their maintainer.  

And I use supervisor to manage these processes. Especially, PHP-FPM7.  
This is the first time for me for using supervisor so I couldn't sure it is needed, but it looks just works. If you have any ideas, please let me know :)  
### All functions work
![all functions work](docs/docker-h5ai-functions.png)
h5ai supports extensional functions such as showing thumnails of audio and video, caching for better speed, etc. This image functions all of them.

## How can I use this?
First of all, it assumes that you have installed Docker on your system.  
Pull the image from docker hub.
```bash
docker pull awesometic/h5ai
```
Run that image temporary. '--rm' option removes container when you terminate the interaction session.
```bash
docker run --name=h5ai --it --rm -p 80:80 -v /where/you/wanna/share:/h5ai/wherever awesometic/h5ai
```
If you want to runs this image permanently, try out the command below.
```bash
docker run --name=h5ai -d -p 80:80 -v /where/you/wanna/share:/h5ai/wherever awesometic/h5ai
```
**IMPORTANT**: Do not place to the whole '/h5ai' directory of the image. If '/h5ai/_h5ai' directory is going to be overwritten then it loses its functioning.

If the container runs, just let your browser browse the below.
```
http://localhost/
```
Then you can see the directories you shared for the image.  

## License
This project comes with MIT license. Please see the [license file](LICENSE).  
