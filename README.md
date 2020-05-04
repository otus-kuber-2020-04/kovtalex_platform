# kovtalex_platform

## Настройка локального окружения. Запуск первого контейнера. Работа с kubectl

### Установка kubectl

**kubectl** - консольная утилита для управления кластерами Kubernetes.

Установим последнюю доступную версию kubectl на локальную машину. Инструкции по установке доступны по [ссылке](https://kubernetes.io/docs/tasks/tools/install-kubectl/).

```console
brew install kubectl
```

И автодополнение для [shell](https://kubernetes.io/docs/reference/kubectl/cheatsheet/#kubectl-autocomplete).

ZSH:

```console
source <(kubectl completion zsh)  # setup autocomplete in zsh into the current shell
echo "[[ $commands[kubectl] ]] && source <(kubectl completion zsh)" >> ~/.zshrc # add autocomplete permanently to your zsh shell
```

### Установка Minikube

**Minikube** - наиболее универсальный вариант для развертывания локального окружения.

Установим последнюю доступную версию Minikube на локальную машину. Инструкции по установке доступны по [ссылке](https://kubernetes.io/docs/tasks/tools/install-minikube/).

```console
brew install minikube
```

### Запуск Minikube

После установки запустим виртуальную машину с кластером Kubernetes командой **minikube start**.

```console
minikube start --vm-driver=docker

😄  minikube v1.9.2 on Darwin 10.15.4
✨  Using the docker driver based on user configuration
👍  Starting control plane node m01 in cluster minikube
🚜  Pulling base image ...
💾  Downloading Kubernetes v1.18.0 preload ...
    > preloaded-images-k8s-v2-v1.18.0-docker-overlay2-amd64.tar.lz4: 542.91 MiB
🔥  Creating Kubernetes in docker container with (CPUs=2) (4 available), Memory=1989MB (1989MB available) ...
🐳  Preparing Kubernetes v1.18.0 on Docker 19.03.2 ...
    ▪ kubeadm.pod-network-cidr=10.244.0.0/16
🌟  Enabling addons: default-storageclass, storage-provisioner
🏄  Done! kubectl is now configured to use "minikube"

❗  /usr/local/bin/kubectl is v1.15.5, which may be incompatible with Kubernetes v1.18.0.
💡  You can also use 'minikube kubectl -- get pods' to invoke a matching version
```

После запуска, Minikube должен автоматически настроить kubectl и создать контекст minikube.  
Посмотреть текущую
конфигурацию kubectl можно командой **kubectl config view**.

Проверим, что подключение к кластеру работает корректно:

```console
kubectl cluster-info

Kubernetes master is running at https://127.0.0.1:32768
KubeDNS is running at https://127.0.0.1:32768/api/v1/namespaces/kube-system/services/kube-dns:dns/proxy

To further debug and diagnose cluster problems, use 'kubectl cluster-info dump'.
```

### Kubernetes Dashboard

Также можно подключить один из наиболее часто устанавливаемых аддонов для Kubernetes - [Dashboard](https://kubernetes.io/docs/tasks/access-application-cluster/web-ui-dashboard/). Но делать мы этого не будем.

### k9s

Удобный способ визуализации консольной работы с кластером - [k9s](https://k9scli.io/).

### Minikube

При установке кластера с использованием Minikube будет создан контейнер docker в котором будут работать все системные компоненты кластера Kubernetes.  
Можем убедиться в этом, зайдем на ВМ по SSH и посмотрим запущенные Docker контейнеры:

```console
minikube ssh

docker@minikube:~$ docker ps

CONTAINER ID        IMAGE                  COMMAND                  CREATED             STATUS              PORTS               NAMES
85937caf79d3        67da37a9a360           "/coredns -conf /etc…"   43 minutes ago      Up 43 minutes                           k8s_coredns_coredns-66bff467f8-p7swh_kube-system_e6bf2e9d-2e19-499d-8a73-8e991702b87e_0
e538bf422acc        67da37a9a360           "/coredns -conf /etc…"   43 minutes ago      Up 43 minutes                           k8s_coredns_coredns-66bff467f8-q4z6m_kube-system_cf396204-7fbb-4d33-b4ec-9388db14d8ee_0
a38019c3596a        4689081edb10           "/storage-provisioner"   43 minutes ago      Up 43 minutes                           k8s_storage-provisioner_storage-provisioner_kube-system_6fac89db-3152-41d5-ac3f-0e0bc3538ae6_0
f2a5bf383bb3        43940c34f24f           "/usr/local/bin/kube…"   43 minutes ago      Up 43 minutes                           k8s_kube-proxy_kube-proxy-c485n_kube-system_c024f4ec-4738-4eb1-906f-106492f0b975_0
e43a4a8f5529        k8s.gcr.io/pause:3.2   "/pause"                 43 minutes ago      Up 43 minutes                           k8s_POD_coredns-66bff467f8-p7swh_kube-system_e6bf2e9d-2e19-499d-8a73-8e991702b87e_0
8742b307d2e0        k8s.gcr.io/pause:3.2   "/pause"                 43 minutes ago      Up 43 minutes                           k8s_POD_coredns-66bff467f8-q4z6m_kube-system_cf396204-7fbb-4d33-b4ec-9388db14d8ee_0
0d69fb536fcb        aa67fec7d7ef           "/bin/kindnetd"          43 minutes ago      Up 43 minutes                           k8s_kindnet-cni_kindnet-rgt42_kube-system_68104c7f-a787-4fcb-a65c-91d51372c1de_0
700e5e2226c7        k8s.gcr.io/pause:3.2   "/pause"                 43 minutes ago      Up 43 minutes                           k8s_POD_storage-provisioner_kube-system_6fac89db-3152-41d5-ac3f-0e0bc3538ae6_0
b44bbd21388a        k8s.gcr.io/pause:3.2   "/pause"                 43 minutes ago      Up 43 minutes                           k8s_POD_kube-proxy-c485n_kube-system_c024f4ec-4738-4eb1-906f-106492f0b975_0
f29c9a711b8f        k8s.gcr.io/pause:3.2   "/pause"                 43 minutes ago      Up 43 minutes                           k8s_POD_kindnet-rgt42_kube-system_68104c7f-a787-4fcb-a65c-91d51372c1de_0
9cd68dda5f76        a31f78c7c8ce           "kube-scheduler --au…"   43 minutes ago      Up 43 minutes                           k8s_kube-scheduler_kube-scheduler-minikube_kube-system_5795d0c442cb997ff93c49feeb9f6386_0
0695ca78733b        303ce5db0e90           "etcd --advertise-cl…"   43 minutes ago      Up 43 minutes                           k8s_etcd_etcd-minikube_kube-system_ca02679f24a416493e1c288b16539a55_0
733c2fef50cf        74060cea7f70           "kube-apiserver --ad…"   43 minutes ago      Up 43 minutes                           k8s_kube-apiserver_kube-apiserver-minikube_kube-system_45e2432c538c36239dfecde67cb91065_0
bed099c2898a        d3e55153f52f           "kube-controller-man…"   43 minutes ago      Up 43 minutes                           k8s_kube-controller-manager_kube-controller-manager-minikube_kube-system_c92479a2ea69d7c331c16a5105dd1b8c_0
ef65a858de32        k8s.gcr.io/pause:3.2   "/pause"                 43 minutes ago      Up 43 minutes                           k8s_POD_etcd-minikube_kube-system_ca02679f24a416493e1c288b16539a55_0
92cefb8f5af9        k8s.gcr.io/pause:3.2   "/pause"                 43 minutes ago      Up 43 minutes                           k8s_POD_kube-scheduler-minikube_kube-system_5795d0c442cb997ff93c49feeb9f6386_0
27fb23d3eceb        k8s.gcr.io/pause:3.2   "/pause"                 43 minutes ago      Up 43 minutes                           k8s_POD_kube-controller-manager-minikube_kube-system_c92479a2ea69d7c331c16a5105dd1b8c_0
4212378acdea        k8s.gcr.io/pause:3.2   "/pause"                 43 minutes ago      Up 43 minutes                           k8s_POD_kube-apiserver-minikube_kube-system_45e2432c538c36239dfecde67cb91065_0
```

Проверим, что Kubernetes обладает некоторой устойчивостью к отказам, удалим все контейнеры:

```console
docker rm -f $(docker ps -a -q)
```

### kubectl

Эти же компоненты, но уже в виде pod можно увидеть в namespace kube-system:

```console
kubectl get pods -n kube-system

NAME                               READY   STATUS    RESTARTS   AGE
coredns-66bff467f8-p7swh           1/1     Running   0          46m
coredns-66bff467f8-q4z6m           1/1     Running   0          46m
etcd-minikube                      1/1     Running   0          47m
kindnet-rgt42                      1/1     Running   0          46m
kube-apiserver-minikube            1/1     Running   0          47m
kube-controller-manager-minikube   1/1     Running   0          47m
kube-proxy-c485n                   1/1     Running   0          46m
kube-scheduler-minikube            1/1     Running   1          47m
storage-provisioner                1/1     Running   0          47m
```

Расшифруем: данной командой мы запросили у API **вывести список** (get) всех **pod** (pods) в **namespace** (-n, сокращенное от --namespace) **kube-system**.

Можно устроить еще одну проверку на прочность и удалить все pod с системными компонентами:

```console
kubectl delete pod --all -n kube-system

pod "coredns-66bff467f8-p7swh" deleted
pod "coredns-66bff467f8-q4z6m" deleted
pod "etcd-minikube" deleted
pod "kindnet-rgt42" deleted
pod "kube-apiserver-minikube" deleted
pod "kube-controller-manager-minikube" deleted
pod "kube-proxy-c485n" deleted
pod "kube-scheduler-minikube" deleted
pod "storage-provisioner" deleted
```

Проверим, что кластер находится в рабочем состоянии, команды **kubectl get cs** или **kubectl get componentstatuses**.

выведут состояние системных компонентов:

```console
kubectl get componentstatuses

NAME                 STATUS    MESSAGE             ERROR
scheduler            Healthy   ok
controller-manager   Healthy   ok
etcd-0               Healthy   {"health":"true"}
```

### Dockerfile

Для выполнения домашней работы создадим Dockerfile, в котором будет описан образ:

1. Запускающий web-сервер на порту 8000
2. Отдающий содержимое директории /app внутри контейнера (например, если в директории /app лежит файл homework.html, то при запуске контейнера данный файл должен быть доступен по URL [http://localhost:8000/homework.html])
3. Работающий с UID 1001

```Dockerfile
FROM nginx:1.18.0-alpine

RUN apk add --no-cache shadow
RUN usermod -u 1001 nginx \
  && groupmod -g 1001 nginx

WORKDIR /app
COPY ./app .

COPY ./default.conf /etc/nginx/conf.d/default.conf
COPY ./nginx.conf /etc/nginx/nginx.conf

EXPOSE 8000
USER 1001
```

После того, как Dockerfile будет готов:

* В корне репозитория создадим директорию kubernetesintro/web и поместим туда готовый Dockerfile
* Соберем из Dockerfile образ контейнера и поместим его в публичный Container Registry (например, Docker Hub)

```console
docker build -t kovtalex/simple-web:0.1 .
docker push kovtalex/simple-web:0.1
```

### Манифест pod

Напишем манифест web-pod.yaml для создания pod **web** c меткой **app** со значением **web**, содержащего один контейнер с названием **web**. Необходимо использовать ранее собранный образ с Docker Hub.

```yml
apiVersion: v1 # Версия API
kind: Pod # Объект, который создаем
metadata:
  name: web # Название Pod
  labels: # Метки в формате key: value
    app: web
spec: # Описание Pod
  containers: # Описание контейнеров внутри Pod
  - name: web # Название контейнера
    image: kovtalex/simple-web:0.1 # Образ из которого создается контейнер
```

Поместим манифест web-pod.yaml в директорию kubernetesintro и применим его:

```console
kubectl apply -f web-pod.yaml

pod/web created
```

После этого в кластере в namespace default должен появиться запущенный pod web:

```console
kubectl get pods

NAME   READY   STATUS    RESTARTS   AGE
web    1/1     Running   0          46s
```

В Kubernetes есть возможность получить манифест уже запущенного в кластере pod.

В подобном манифесте помимо описания pod будутфигурировать служебные поля (например, различные статусы) и значения, подставленные по умолчанию:

```console
kubectl get pod web -o yaml
```

### kubectl describe

Другой способ посмотреть описание pod - использовать ключ **describe**. Команда позволяет отследить текущее состояние объекта, а также события, которые с ним происходили:

```console
kubectl describe pod web
```

Успешный старт pod в kubectl describe выглядит следующим образом:

* scheduler определил, на какой ноде запускать pod
* kubelet скачал необходимый образ и запустил контейнер

```console
Events:
  Type    Reason     Age    From               Message
  ----    ------     ----   ----               -------
  Normal  Scheduled  3m23s  default-scheduler  Successfully assigned default/web to minikube
  Normal  Pulled     3m22s  kubelet, minikube  Container image "kovtalex/simple-web:0.1" already present on machine
  Normal  Created    3m22s  kubelet, minikube  Created container web
  Normal  Started    3m22s  kubelet, minikube  Started container web
```

При этом **kubectl describe** - хороший старт для поиска причин проблем с запуском pod.

Укажем в манифесте несуществующий тег образа web и применим его заново (kubectl apply -f web-pod.yaml).

Статус pod (kubectl get pods) должен измениться на **ErrImagePull/ImagePullBackOff**, а команда **kubectl describe pod web** поможет понять причину такого поведения:

```console
Events:
  Warning  Failed     12s               kubelet, minikube  Failed to pull image "kovtalex/simple-web:0.2": rpc error: code = Unknown desc = Error response from daemon: manifest for kovtalex/simple-web:0.2 not found: manifest unknown: manifest unknown
  Warning  Failed     12s               kubelet, minikube  Error: ErrImagePull
  Normal   BackOff    12s               kubelet, minikube  Back-off pulling image "kovtalex/simple-web:0.2"
  Warning  Failed     12s               kubelet, minikube  Error: ImagePullBackOff
  Normal   Pulling    0s (x2 over 14s)  kubelet, minikube  Pulling image "kovtalex/simple-web:0.2"
```

Вывод **kubectl describe pod web** если мы забыли, что Container Registry могут быть приватными:

```console
Events:
  Warning Failed 2s kubelet, minikube Failed to pull image "quay.io/example/web:1.0": rpc error: code = Unknown desc =Error response from daemon: unauthorized: access to the requested resource is not authorized
```

### Init контейнеры

Добавим в наш pod [init контейнер](https://kubernetes.io/docs/concepts/workloads/pods/init-containers/), генерирующий страницу index.html.

**Init контейнеры** описываются аналогично обычным контейнерам в pod. Добавим в манифест web-pod.yaml описание init контейнера, соответствующее следующим требованиям:

* **image** init контейнера должен содержать **wget** (например, можно использовать busybox:1.31.0 или любой другой busybox актуальной версии)
* command init контейнера (аналог ENTRYPOINT в Dockerfile) укажите следующую:

```console
['sh', '-c', 'wget -O- https://tinyurl.com/otus-k8s-intro | sh']
```

### Volumes

Для того, чтобы файлы, созданные в **init контейнере**, были доступны основному контейнеру в pod нам понадобится использовать **volume** типа **emptyDir**.

У контейнера и у **init контейнера** должны быть описаны **volumeMounts** следующего вида:

```yml
volumeMounts:
- name: app
  mountPath: /app
```

web-pod.yaml

```yml
apiVersion: v1 # Версия API
kind: Pod # Объект, который создаем
metadata:
  name: web # Название Pod
  labels: # Метки в формате key: value
    app: web
spec: # Описание Pod
  containers: # Описание контейнеров внутри Pod
  - name: web # Название контейнера
    image: kovtalex/simple-web:0.1 # Образ из которого создается контейнер
    volumeMounts:
    - name: app
      mountPath: /app    
  initContainers:
  - name: init-web
    image: busybox:1.31.1
    command: ['sh', '-c', 'wget -O- https://tinyurl.com/otus-k8s-intro | sh']
    volumeMounts:
    - name: app
      mountPath: /app  
  volumes:
  - name: app
    emptyDir: {}
```

### Запуск pod

Удалим запущенный pod web из кластера **kubectl delete pod web** и примените обновленный манифест web-pod.yaml

Отслеживать происходящее можно с использованием команды **kubectl get pods -w**

Должен получиться аналогичный вывод:

```console
kubectl get pods -w
NAME   READY   STATUS     RESTARTS   AGE
web    0/1     Init:0/1   0          2s
web    0/1     Init:0/1   0          2s
web    0/1     PodInitializing   0          3s
web    1/1     Running           0          4s
```

### Проверка работы приложения

Проверим работоспособность web сервера. Существует несколько способов получить доступ к pod, запущенным внутри кластера.

Мы воспользуемся командой [kubectl port-forward](https://kubernetes.io/docs/tasks/access-application-cluster/port-forward-access-application-cluster/)

```console
kubectl port-forward --address 0.0.0.0 pod/web 8000:8000
```

Если все выполнено правильно, на локальном компьютере по ссылке <http://localhost:8000/index.html> должна открыться страница.

### kube-forwarder

В качестве альтернативы **kubectl port-forward** можно использовать удобную обертку [kube-forwarder](https://kube-forwarder.pixelpoint.io/). Она отлично подходит для доступа к pod внутри кластера с локальной машины во время разработки продукта.

### Hipster Shop

Давайте познакомимся с [приложением](https://github.com/GoogleCloudPlatform/microservices-demo) поближе и попробуем запустить внутри нашего кластера его компоненты.

Начнем с микросервиса **frontend**. Его исходный код доступен по [адресу](https://github.com/GoogleCloudPlatform/microservices-demo).

* Склонируем [репозиторий](https://github.com/GoogleCloudPlatform/microservices-demo) и соберем собственный образ для **frontend** (используем готовый Dockerfile)
* Поместим собранный образ на Docker Hub

```console
git clone https://github.com/GoogleCloudPlatform/microservices-demo.git
docker build -t kovtalex/hipster-frontend:v0.0.1 .
docker push kovtalex/hipster-frontend:v0.0.1
```

Рассмотрим альтернативный способ запуска pod в нашем Kubernetes кластере.

Мы уже умеем работать с манифестами (и это наиболее корректный подход к развертыванию ресурсов в Kubernetes), но иногда бывает удобно использовать ad-hoc режим и возможности Kubectl для создания ресурсов.

Разберем пример для запуска **frontend** pod:

```console
kubectl run frontend --image kovtalex/hipster-frontend:v0.0.1 --restart=Never
```

* **kubectl run** - запустить ресурс
* **frontend** - с именем frontend
* **--image** - из образа kovtalex/hipster-frontend:v0.0.1 (подставьте свой образ)
* **--restart=Never** указываем на то, что в качестве ресурса запускаем pod. [Подробности](https://kubernetes.io/docs/reference/kubectl/conventions/)

Один из распространенных кейсов использования ad-hoc режима - генерация манифестов средствами kubectl:

```console
kubectl run frontend --image kovtalex/hipster-frontend:v0.0.1 --restart=Never --dryrun -o yaml > frontend-pod.yaml
```

Рассмотрим дополнительные ключи:

* **--dry-run** - вывод информации о ресурсе без его реального создания
* **-o yaml** - форматирование вывода в YAML
* **> frontend-pod.yaml** - перенаправление вывода в файл

### Hipster Shop | Задание со ⭐

* Выясним причину, по которой pod **frontend** находится в статусе **Error**
* Создадим новый манифест **frontend-pod-healthy.yaml**. При его применении ошибка должна исчезнуть. Подсказки можно найти:
  * В логах - **kubectl logs frontend**
  * В манифесте по [ссылке](https://github.com/GoogleCloudPlatform/microservices-demo/blob/master/kubernetes-manifests/frontend.yaml)
* В результате, после применения исправленного манифеста pod **frontend** должен находиться в статусе **Running**
* Поместим исправленный манифест **frontend-pod-healthy.yaml** в директорию **kubernetes-intro**

1. Проверив лог pod можно заметить, что не заданы переменные окружения. Добавим их.
2. Так же можно свериться со списком необходимых переменных окружения из готового манифеста.
3. Добавим отсутствующие переменные окружения в наш yaml файл и пересоздадим pod.

```yml
- name: PRODUCT_CATALOG_SERVICE_ADDR
  value: "productcatalogservice:3550"
- name: CURRENCY_SERVICE_ADDR
  value: "currencyservice:7000"
- name: CART_SERVICE_ADDR
  value: "cartservice:7070"
- name: RECOMMENDATION_SERVICE_ADDR
  value: "recommendationservice:8080"
- name: SHIPPING_SERVICE_ADDR
  value: "shippingservice:50051"
- name: CHECKOUT_SERVICE_ADDR
  value: "checkoutservice:5050"
- name: AD_SERVICE_ADDR
  value: "adservice:9555"
```

**frontend**  в статусе Running.

```console
kubectl get pods

NAME       READY   STATUS    RESTARTS   AGE
frontend   1/1     Running   0          10s
```
