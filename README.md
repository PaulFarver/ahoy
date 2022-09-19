# Ahoy

An exercise in docker and kubernetes

## Introduction

The point of this workshop is to familiarize yourself with docker and kubernetes  
This repository includes a small golang chat server, with an embedded frontend.  
Your goal is to get this server to run in a cloud environment.  
If you feel lost or confused, don't hesitate to ask or look for solutions online.

## Prerequisites

- docker `brew install docker`
- kubectl `brew install kubernetes-cli`
- aws `brew install aws-cli`

## 0. Getting aboard (Running locally)

The chat server relies on a connection to a redis server in order to send messages.  
We can use the public docker image for redis to test out the server locally: https://hub.docker.com/_/redis

> Start redis server locally and expose it's port, so you can try out the chat server

you can start the chat server with `go run main.go`

## 1. Untying the lines (Building a docker image)

Our next order of business is to get our go server to run in a docker container.  
For that we will need to build a docker image, so that we have something to base our container on.

> Write a dockerfile, that builds the go server

You can build a docker image from a Dockerfile with `docker build .`

## 2. Pulling the anchor (Running in docker compose)

A solution for orchestration when running docker containers locally is docker compose  
We can use docker compose to define and run multiple containers in a single file rather
than having to run complicated `docker run` commands all the time.

> Write a docker-compose.yml file and run the chat and redis servers with `docker compose up`
>
> > BONUS: What do the following terms mean in docker: image, container, repository, tag and registry

## 3. Setting sail (Running in kubernetes)

Kubernetes is a great solution for orchestration in the cloud.  
Similarly to docker compose, it allows us to define a set of containers we want to run.  
The difference is that we don't have to manually tell kubernetes to start the containers.  
We simply give kubernetes our manifest, and kubernetes will continuously try to make sure that the containers are running somewhere on some maching.  
Kubernetes does not operate directly on containers, though. Instead it manages what it calls Pods.  
Pods are a collection of containers along with some metadata attached to them.

A simple manifest with a pod could look like this:

```yaml
# manifest.yaml
apiVersion: v1
kind: Pod
metadata:
  name: my-pod
  namespace: my-namespace
spec:
  containers:
    - name: alpine
      image: alpine:3.16
      command:
        - echo
        - "hello, mom"
```

In order to give it to kubernetes we can use kubectl like so

```sh
$ kubectl apply -f manifest.yaml
pod/my-pod created
```

And kubernetes will then schedule a pod with on a machine in the cluster.

We can get the status of our pod with

```sh
$ kubectl get pod --namespace my-namespace
NAME      READY   STATUS             RESTARTS     AGE
my-pod    0/1     CrashLoopBackOff   1 (8s ago)   11s
```

Notice that the pod has the `CrashLoopBackOff` status. This happens when kubernetes continuously restarts the containers in the pod, but they keep crashing.  
The reason the container crashes is of course the entrypoint of the container finishes immediately, so the container dies.

We can get the logs of the pod with

```sh
$ kubectl logs my-pod --namespace my-namespace
hello, mom
```

Where we can see that the container indeed did as we asked.

> Write a pod manifest containing a redis and a chat server, and apply it to kubernetes

You'll have to push your docker image to a docker registry. You can use ttl.sh simply with

```sh
docker build . -t ttl.sh/my-image-with-some-id:2h
docker push ttl.sh/my-image-with-some-id:2h
```

and now that image will be available to other clients to pull with

```sh
docker pull ttl.sh/my-image-with-some-id:2h
```
