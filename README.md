# kovtalex_platform

## Volumes, Storages, StatefulSet

### Установка и запуск kind

**kind** - инструмент для запуска Kuberenetes при помощи Docker контейнеров.

Запуск: kind create cluster

### Применение StatefulSet

В этом ДЗ мы развернем StatefulSet c [MinIO](https://min.io/) - локальным S3 хранилищем.

Конфигурация [StatefulSet](https://raw.githubusercontent.com/express42/otus-platform-snippets/master/Module-02/Kuberenetes-volumes/minio-statefulset.yaml).

minio-statefulset.yaml

```yml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  # This name uniquely identifies the StatefulSet
  name: minio
spec:
  serviceName: minio
  replicas: 1
  selector:
    matchLabels:
      app: minio # has to match .spec.template.metadata.labels
  template:
    metadata:
      labels:
        app: minio # has to match .spec.selector.matchLabels
    spec:
      containers:
      - name: minio
        env:
        - name: MINIO_ACCESS_KEY
          value: "minio"
        - name: MINIO_SECRET_KEY
          value: "minio123"
        image: minio/minio:RELEASE.2019-07-10T00-34-56Z
        args:
        - server
        - /data 
        ports:
        - containerPort: 9000
        # These volume mounts are persistent. Each pod in the PetSet
        # gets a volume mounted based on this field.
        volumeMounts:
        - name: data
          mountPath: /data
        # Liveness probe detects situations where MinIO server instance
        # is not working properly and needs restart. Kubernetes automatically
        # restarts the pods if liveness checks fail.
        livenessProbe:
          httpGet:
            path: /minio/health/live
            port: 9000
          initialDelaySeconds: 120
          periodSeconds: 20
  # These are converted to volume claims by the controller
  # and mounted at the paths mentioned above. 
  volumeClaimTemplates:
  - metadata:
      name: data
    spec:
      accessModes:
        - ReadWriteOnce
      resources:
        requests:
          storage: 10Gi
```

### Применение Headless Service

Для того, чтобы наш StatefulSet был доступен изнутри кластера, создадим [Headless Service](https://raw.githubusercontent.com/express42/otus-platform-snippets/master/Module-02/Kuberenetes-volumes/minio-headless-service.yaml).

minio-headlessservice.yaml

```yml
apiVersion: v1
kind: Service
metadata:
  name: minio
  labels:
    app: minio
spec:
  clusterIP: None
  ports:
    - port: 9000
      name: minio
  selector:
    app: minio
```

В результате применения конфигурации должно произойти следующее:

- Запуститься под с MinIO
- Создаться PVC
- Динамически создаться PV на этом PVC с помощью дефолотного StorageClass

```console
kubectl apply -f minio-statefulset.yaml
statefulset.apps/minio created

kubectl apply -f minio-headlessservice.yaml
service/minio created
```

### Проверка работы MinIO

Создадим сервис LB:

minio-svc-lb.yaml

```yml
apiVersion: v1
kind: Service
metadata:
  name: minio-svc-lb
spec:
  selector:
    app: minio
  type: LoadBalancer
  ports:
    - protocol: TCP
      port: 9000
      targetPort: 9000
```

- Проверить работу Minio можно с помощью консольного клиента [mc](https://github.com/minio/mc)

```console
mc config host add minio http://172.17.255.1:9000 minio minio123
Added `minio` successfully.
```

- Проверить работу Minio можно с помощью браузера: <http://172.17.255.1:9000/minio/>

Также для проверки ресурсов k8s помогут команды:

```console
kubectl get statefulsets
kubectl get pods
kubectl get pvc
kubectl get pv
kubectl describe <resource> <resource_name>
```

```console
kubectl get statefulsets
NAME    READY   AGE
minio   1/1     10h
```

```console
kubectl get pods
NAME      READY   STATUS    RESTARTS   AGE
minio-0   1/1     Running   0          10h
```

```console
kubectl get pvc
NAME           STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS   AGE
data-minio-0   Bound    pvc-905bcd19-8e21-41a3-902b-a75a80b2c4dc   10Gi       RWO            standard       10h
```

```console
kubectl get pv
NAME                                       CAPACITY   ACCESS MODES   RECLAIM POLICY   STATUS   CLAIM                  STORAGECLASS   REASON   AGE
pvc-30f9d611-009d-4b70-90c1-4eee8b707cfe   10Gi       RWO            Delete           Bound    default/data-minio-0   standard                7h7m
```

### Задание со *

В конфигурации нашего StatefulSet данные указаны в открытом виде, что не безопасно.  
Поместим данные в [secrets](https://kubernetes.io/docs/concepts/configuration/secret/) и настроим конфигурацию на их использование.

Конвертируем username и password в base64:

```console
echo -n 'minio' | base64
bWluaW8=

echo -n 'minio123' | base64
bWluaW8xMjM=
```

Подготовим манифест с Secret:

```yml
apiVersion: v1
kind: Secret
metadata:
  name: minio
type: Opaque
data:
  username: bWluaW8=
  password: bWluaW8xMjM=
```

Изменим minio-headlessservice.yaml для использования нашего Secret:

```yml
        env:
        - name: MINIO_ACCESS_KEY
          valueFrom:
            secretKeyRef:
              name: minio
              key: username
        - name: MINIO_SECRET_KEY
          valueFrom:
            secretKeyRef:
              name: minio
              key: password
```

Применим изменения:

```console
kubectl apply -f minio-statefulset.yaml
statefulset.apps/minio configured
secret/minio created
```

Посмотрим на Secret:

```console
kubectl get secret minio -o yaml
apiVersion: v1
data:
  password: bWluaW8xMjM=
  username: bWluaW8=
kind: Secret
metadata:
  annotations:
    kubectl.kubernetes.io/last-applied-configuration: |
      {"apiVersion":"v1","data":{"password":"bWluaW8xMjM=","username":"bWluaW8="},"kind":"Secret","metadata":{"annotations":{},"name":"minio","namespace":"default"},"type":"Opaque"}
  creationTimestamp: "2020-05-23T12:33:55Z"
  managedFields:
  - apiVersion: v1
    fieldsType: FieldsV1
    fieldsV1:
      f:data:
        .: {}
        f:password: {}
        f:username: {}
      f:metadata:
        f:annotations:
          .: {}
          f:kubectl.kubernetes.io/last-applied-configuration: {}
      f:type: {}
    manager: kubectl
    operation: Update
    time: "2020-05-23T12:33:55Z"
  name: minio
  namespace: default
  resourceVersion: "19218"
  selfLink: /api/v1/namespaces/default/secrets/minio
  uid: 87e39a34-4a5b-40c0-a4b9-5181b0a3cb34
type: Opaque
```

```console
kubectl describe statefulsets minio
Name:               minio
Namespace:          default
CreationTimestamp:  Fri, 22 May 2020 23:38:47 +0300
Selector:           app=minio
Labels:             <none>
Annotations:        kubectl.kubernetes.io/last-applied-configuration:
                      {"apiVersion":"apps/v1","kind":"StatefulSet","metadata":{"annotations":{},"name":"minio","namespace":"default"},"spec":{"replicas":1,"sele...
Replicas:           1 desired | 1 total
Update Strategy:    RollingUpdate
  Partition:        824642936636
Pods Status:        1 Running / 0 Waiting / 0 Succeeded / 0 Failed
Pod Template:
  Labels:  app=minio
  Containers:
   minio:
    Image:      minio/minio:RELEASE.2019-07-10T00-34-56Z
    Port:       9000/TCP
    Host Port:  0/TCP
    Args:
      server
      /data
    Liveness:  http-get http://:9000/minio/health/live delay=120s timeout=1s period=20s #success=1 #failure=3
    Environment:
      MINIO_ACCESS_KEY:  minio
      MINIO_SECRET_KEY:  minio123
    Mounts:
      /data from data (rw)
  Volumes:  <none>
Volume Claims:
  Name:          data
  StorageClass:  
  Labels:        <none>
  Annotations:   <none>
  Capacity:      10Gi
  Access Modes:  [ReadWriteOnce]
Events:
  Type    Reason            Age   From                    Message
  ----    ------            ----  ----                    -------
  Normal  SuccessfulCreate  11h   statefulset-controller  create Claim data-minio-0 Pod minio-0 in StatefulSet minio success
  Normal  SuccessfulCreate  11h   statefulset-controller  create Pod minio-0 in StatefulSet minio successful
```

## Удаление кластера

Удалить кластер можно командой: kind delete cluster

## Сетевое взаимодействие Pod, сервисы

### Добавление проверок Pod

- Откроем файл с описанием Pod из предыдущего ДЗ **kubernetes-intro/web-pod.yml**
- Добавим в описание пода **readinessProbe**

```yml
    readinessProbe:
      httpGet:
        path: /index.html
        port: 80
```

- Запустим наш под командой **kubectl apply -f webpod.yml**

```console
kubectl apply -f web-pod.yaml
pod/web created
```

- Теперь выполним команду **kubectl get pod/web** и убедимся, что под перешел в состояние Running

```console
kubectl get pod/web

NAME   READY   STATUS    RESTARTS   AGE
web    0/1     Running   0          45s
```

Теперь сделаем команду **kubectl describe pod/web** (вывод объемный, но в нем много интересного)

- Посмотрим в конце листинга на список **Conditions**:

```console
kubectl describe pod/web

Conditions:
  Type              Status
  Initialized       True
  Ready             False
  ContainersReady   False
  PodScheduled      True
```

Также посмотрим на список событий, связанных с Pod:

```console
Events:
  Type     Reason     Age               From               Message
  ----     ------     ----              ----               -------
  Warning  Unhealthy  3s (x2 over 13s)  kubelet, minikube  Readiness probe failed: Get http://172.18.0.4:80/index.html: dial tcp 172.18.0.4:80: connect: connection refused
```

Из листинга выше видно, что проверка готовности контейнера завершается неудачно. Это неудивительно - вебсервер в контейнере слушает порт 8000 (по условиям первого ДЗ).

Пока мы не будем исправлять эту ошибку, а добавим другой вид проверок: **livenessProbe**.

- Добавим в манифест проверку состояния веб-сервера:

```yml
    livenessProbe:
      tcpSocket: { port: 8000 }
```

- Запустим Pod с новой конфигурацией:

```console
kubectl apply -f web-pod.yaml
pod/web created

kubectl get pod/web
NAME   READY   STATUS    RESTARTS   AGE
web    0/1     Running   0          17s
```

Вопрос для самопроверки:

- Почему следующая конфигурация валидна, но не имеет смысла?

```yml
livenessProbe:
  exec:
    command:
      - 'sh'
      - '-c'
      - 'ps aux | grep my_web_server_process'
```

> Данная конфигурация не имеет смысла, так как не означает, что работающий веб сервер без ошибок отдает веб страницы.

- Бывают ли ситуации, когда она все-таки имеет смысл?

> Возможно, когда требуется проверка работы сервиса без доступа к нему из вне.

### Создание Deployment

В процессе изменения конфигурации Pod, мы столкнулись с неудобством обновления конфигурации пода через **kubectl** (и уже нашли ключик **--force** ).

В любом случае, для управления несколькими однотипными подами такой способ не очень подходит.  
Создадим **Deployment**, который упростит обновление конфигурации пода и управление группами подов.

- Для начала, создадим новую папку **kubernetes-networks** в нашем репозитории
- В этой папке создадим новый файл **web-deploy.yaml**

Начнем заполнять наш файл-манифест для Deployment:

```yml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web     # Название нашего объекта Deployment
spec:
  replicas: 1    # Начнем с одного пода
  selector:      # Укажем, какие поды относятся к нашему Deployment:
    matchLabels: # - это поды с меткой
      app: web   # app и ее значением web
  template:      # Теперь зададим шаблон конфигурации пода
    metadata:
      name: web # Название Pod
      labels: # Метки в формате key: value
        app: web
    spec: # Описание Pod
      containers: # Описание контейнеров внутри Pod
      - name: web # Название контейнера
        image: kovtalex/simple-web:0.1 # Образ из которого создается контейнер
        readinessProbe:
          httpGet:
            path: /index.html
            port: 80
        livenessProbe:
          tcpSocket: { port: 8000 }
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

- Для начала удалим старый под из кластера:

```console
kubectl delete pod/web --grace-period=0 --force
pod "web" deleted
```

- И приступим к деплою:

```console
kubectl apply -f web-deploy.yaml
deployment.apps/web created
```

- Посмотрим, что получилось:

```console
kubectl describe deployment web

Conditions:
  Type           Status  Reason
  ----           ------  ------
  Available      False   MinimumReplicasUnavailable
  Progressing    True    ReplicaSetUpdated
OldReplicaSets:  <none>
NewReplicaSet:   web-dbfcc8c76 (1/1 replicas created)
Events:
  Type    Reason             Age   From                   Message
  ----    ------             ----  ----                   -------
  Normal  ScalingReplicaSet  57s   deployment-controller  Scaled up replica set web-dbfcc8c76 to 1
```

- Поскольку мы не исправили **ReadinessProbe** , то поды, входящие в наш **Deployment**, не переходят в состояние Ready из-за неуспешной проверки
- Это влияет На состояние всего **Deployment** (строчка Available в блоке Conditions)
- Теперь самое время исправить ошибку! Поменяем в файле web-deploy.yaml следующие параметры:
  - Увеличим число реплик до 3 ( replicas: 3 )
  - Исправим порт в readinessProbe на порт 8000

```yml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web     # Название нашего объекта Deployment
spec:
  replicas: 3
  selector:      # Укажем, какие поды относятся к нашему Deployment:
    matchLabels: # - это поды с меткой
      app: web   # app и ее значением web
  template:      # Теперь зададим шаблон конфигурации пода
    metadata:
      name: web # Название Pod
      labels: # Метки в формате key: value
        app: web
    spec: # Описание Pod
      containers: # Описание контейнеров внутри Pod
      - name: web # Название контейнера
        image: kovtalex/simple-web:0.1 # Образ из которого создается контейнер
        readinessProbe:
          httpGet:
            path: /index.html
            port: 8000
        livenessProbe:
          tcpSocket: { port: 8000 }
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

- Применим изменения командой kubectl apply -f webdeploy.yaml

```console
kubectl apply -f web-deploy.yaml
deployment.apps/web configured
```

- Теперь проверим состояние нашего **Deployment** командой kubectl describe deploy/web и убедимся, что условия (Conditions) Available и Progressing выполняются (в столбце Status значение true)

```console
kubectl describe deployment web

Conditions:
  Type           Status  Reason
  ----           ------  ------
  Available      True    MinimumReplicasAvailable
  Progressing    True    NewReplicaSetAvailable
```

- Добавим в манифест ( web-deploy.yaml ) блок **strategy** (можно сразу перед шаблоном пода)

```yml
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 0
      maxSurge: 100%
```

- Применим изменения

```console
kubectl apply -f web-deploy.yaml
deployment.apps/web configured
```

```console
ROLLOUT STATUS:
- [Current rollout | Revision 8] [MODIFIED]  default/web-6596d967d4
    ⌛ Waiting for ReplicaSet to attain minimum available Pods (0 available of a 3 minimum)
       - [ContainersNotInitialized] web-6596d967d4-gvmlp containers with incomplete status: [init-web]
       - [ContainersNotReady] web-6596d967d4-gvmlp containers with unready status: [web]
       - [ContainersNotInitialized] web-6596d967d4-rz68n containers with incomplete status: [init-web]
       - [ContainersNotReady] web-6596d967d4-rz68n containers with unready status: [web]
       - [ContainersNotInitialized] web-6596d967d4-lzjlf containers with incomplete status: [init-web]
       - [ContainersNotReady] web-6596d967d4-lzjlf containers with unready status: [web]

- [Previous ReplicaSet | Revision 7] [MODIFIED]  default/web-54c8466885
    ⌛ Waiting for ReplicaSet to scale to 0 Pods (3 currently exist)
       - [Ready] web-54c8466885-rmwnb
       - [Ready] web-54c8466885-hf7bh
       - [Ready] web-54c8466885-jxqgk
```

> добавляются сразу 3 новых пода

- Попробуем разные варианты деплоя с крайними значениями maxSurge и maxUnavailable (оба 0, оба 100%, 0 и 100%)
- За процессом можно понаблюдать с помощью kubectl get events --watch или установить [kubespy](https://github.com/pulumi/kubespy) и использовать его **kubespy trace deploy**

```yml
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 0
      maxSurge: 0
```

```console
kubectl apply -f web-deploy.yaml

The Deployment "web" is invalid: spec.strategy.rollingUpdate.maxUnavailable: Invalid value: intstr.IntOrString{Type:0, IntVal:0, StrVal:""}: may not be 0 when `maxSurge` is 0
```

> оба значения не могут быть одновременно равны 0

```yml
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 100%
      maxSurge: 0
```

```console
ROLLOUT STATUS:
- [Current rollout | Revision 7] [MODIFIED]  default/web-54c8466885
    ⌛ Waiting for ReplicaSet to attain minimum available Pods (0 available of a 3 minimum)
       - [ContainersNotReady] web-54c8466885-hf7bh containers with unready status: [web]
       - [ContainersNotReady] web-54c8466885-jxqgk containers with unready status: [web]
       - [ContainersNotReady] web-54c8466885-rmwnb containers with unready status: [web]
```

> удаление 3 старых подов и затем создание трех новых

```yml
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 100%
      maxSurge: 100%
```

```console
kubectl get events -w

0s          Normal    Scheduled                 pod/web-54c8466885-b8lvv    Successfully assigned default/web-54c8466885-b8lvv to minikube
0s          Normal    Killing                   pod/web-6596d967d4-chgtq    Stopping container web
0s          Normal    Scheduled                 pod/web-54c8466885-v2229    Successfully assigned default/web-54c8466885-v2229 to minikube
0s          Normal    Scheduled                 pod/web-54c8466885-xjtgn    Successfully assigned default/web-54c8466885-xjtgn to minikube
0s          Normal    Killing                   pod/web-6596d967d4-qcgkv    Stopping container web
0s          Normal    Killing                   pod/web-6596d967d4-678v7    Stopping container web
0s          Normal    Pulled                    pod/web-54c8466885-b8lvv    Container image "busybox:1.31.1" already present on machine
0s          Normal    Created                   pod/web-54c8466885-b8lvv    Created container init-web
0s          Normal    Pulled                    pod/web-54c8466885-v2229    Container image "busybox:1.31.1" already present on machine
0s          Normal    Pulled                    pod/web-54c8466885-xjtgn    Container image "busybox:1.31.1" already present on machine
0s          Normal    Created                   pod/web-54c8466885-v2229    Created container init-web
0s          Normal    Created                   pod/web-54c8466885-xjtgn    Created container init-web
0s          Normal    Started                   pod/web-54c8466885-b8lvv    Started container init-web
0s          Normal    Started                   pod/web-54c8466885-v2229    Started container init-web
0s          Normal    Started                   pod/web-54c8466885-xjtgn    Started container init-web
0s          Normal    Pulled                    pod/web-54c8466885-xjtgn    Container image "kovtalex/simple-web:0.2" already present on machine
0s          Normal    Pulled                    pod/web-54c8466885-v2229    Container image "kovtalex/simple-web:0.2" already present on machine
0s          Normal    Pulled                    pod/web-54c8466885-b8lvv    Container image "kovtalex/simple-web:0.2" already present on machine
0s          Normal    Created                   pod/web-54c8466885-xjtgn    Created container web
0s          Normal    Created                   pod/web-54c8466885-v2229    Created container web
0s          Normal    Created                   pod/web-54c8466885-b8lvv    Created container web
0s          Normal    Started                   pod/web-54c8466885-xjtgn    Started container web
0s          Normal    Started                   pod/web-54c8466885-v2229    Started container web
0s          Normal    Started                   pod/web-54c8466885-b8lvv    Started container web
```

> Одновременное удаление трех старых и создание трех новых подов

### Создание Service

Для того, чтобы наше приложение было доступно внутри кластера (а тем более - снаружи), нам потребуется объект типа **Service** . Начнем с самого распространенного типа сервисов - **ClusterIP**.

- ClusterIP выделяет для каждого сервиса IP-адрес из особого диапазона (этот адрес виртуален и даже не настраивается на сетевых интерфейсах)
- Когда под внутри кластера пытается подключиться к виртуальному IP-адресу сервиса, то нода, где запущен под меняет адрес получателя в сетевых пакетах на настоящий адрес пода.
- Нигде в сети, за пределами ноды, виртуальный ClusterIP не встречается.

ClusterIP удобны в тех случаях, когда:

- Нам не надо подключаться к конкретному поду сервиса
- Нас устраивается случайное расределение подключений между подами
- Нам нужна стабильная точка подключения к сервису, независимая от подов, нод и DNS-имен

Например:

- Подключения клиентов к кластеру БД (multi-read) или хранилищу
- Простейшая (не совсем, use IPVS, Luke) балансировка нагрузки внутри кластера

Итак, создадим манифест для нашего сервиса в папке kubernetes-networks.

- Файл web-svc-cip.yaml:

```yml
apiVersion: v1
kind: Service
metadata:
  name: web-svc-cip
spec:
  selector:
    app: web
  type: ClusterIP
  ports:
    - protocol: TCP
      port: 80
      targetPort: 8000
```

- Применим изменения: kubectl apply -f web-svc-cip.yaml

```console
kubectl apply -f web-svc-cip.yaml
service/web-svc-cip created
```

- Проверим результат (отметим назначенный CLUSTER-IP):

```console
kubectl get svc

NAME          TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)   AGE
kubernetes    ClusterIP   10.96.0.1      <none>        443/TCP   41m
web-svc-cip   ClusterIP   10.97.60.103   <none>        80/TCP    13s
```

Подключимся к ВМ Minikube (команда minikube ssh и затем sudo -i ):

- Сделаем curl <http://10.97.60.103/index.html> - работает!

```console
sudo -i
curl http://10.97.60.103/index.html
```

- Сделаем ping 10.97.60.103 - пинга нет

```console
ping 10.97.60.103
PING 10.97.60.103 (10.97.60.103) 56(84) bytes of data.
```

- Сделаем arp -an , ip addr show - нигде нет ClusterIP
- Сделаем iptables --list -nv -t nat - вот где наш кластерный IP!

```console
iptables --list -nv -t nat

Chain PREROUTING (policy ACCEPT 1 packets, 60 bytes)
 pkts bytes target     prot opt in     out     source               destination
   39  2627 KUBE-SERVICES  all  --  *      *       0.0.0.0/0            0.0.0.0/0            /* kubernetes service portals */
    7   420 DOCKER     all  --  *      *       0.0.0.0/0            0.0.0.0/0            ADDRTYPE match dst-type LOCAL

Chain INPUT (policy ACCEPT 1 packets, 60 bytes)
 pkts bytes target     prot opt in     out     source               destination

Chain OUTPUT (policy ACCEPT 62 packets, 3720 bytes)
 pkts bytes target     prot opt in     out     source               destination
 2551  154K KUBE-SERVICES  all  --  *      *       0.0.0.0/0            0.0.0.0/0            /* kubernetes service portals */
  349 20940 DOCKER     all  --  *      *       0.0.0.0/0           !127.0.0.0/8          ADDRTYPE match dst-type LOCAL

Chain POSTROUTING (policy ACCEPT 18 packets, 1080 bytes)
 pkts bytes target     prot opt in     out     source               destination
 2728  165K KUBE-POSTROUTING  all  --  *      *       0.0.0.0/0            0.0.0.0/0            /* kubernetes postrouting rules */
   10   657 MASQUERADE  all  --  *      !docker0  172.18.0.0/16        0.0.0.0/0
 1424 86064 KIND-MASQ-AGENT  all  --  *      *       0.0.0.0/0            0.0.0.0/0            ADDRTYPE match dst-type !LOCAL /* kind-masq-agent: ensure nat POSTROUTING directs all non-LOCAL destination traffic to our custom KIND-MASQ-AGENT chain */

Chain DOCKER (2 references)
 pkts bytes target     prot opt in     out     source               destination
    0     0 RETURN     all  --  docker0 *       0.0.0.0/0            0.0.0.0/0

Chain KIND-MASQ-AGENT (1 references)
 pkts bytes target     prot opt in     out     source               destination
    0     0 RETURN     all  --  *      *       0.0.0.0/0            10.244.0.0/16        /* kind-masq-agent: local traffic is not subject to MASQUERADE */
 1424 86064 MASQUERADE  all  --  *      *       0.0.0.0/0            0.0.0.0/0            /* kind-masq-agent: outbound traffic is subject to MASQUERADE (must be last in chain) */

Chain KUBE-KUBELET-CANARY (0 references)
 pkts bytes target     prot opt in     out     source               destination

Chain KUBE-MARK-DROP (0 references)
 pkts bytes target     prot opt in     out     source               destination
    0     0 MARK       all  --  *      *       0.0.0.0/0            0.0.0.0/0            MARK or 0x8000

Chain KUBE-MARK-MASQ (15 references)
 pkts bytes target     prot opt in     out     source               destination
    0     0 MARK       all  --  *      *       0.0.0.0/0            0.0.0.0/0            MARK or 0x4000

Chain KUBE-NODEPORTS (1 references)
 pkts bytes target     prot opt in     out     source               destination

Chain KUBE-POSTROUTING (1 references)
 pkts bytes target     prot opt in     out     source               destination
    0     0 MASQUERADE  all  --  *      *       0.0.0.0/0            0.0.0.0/0            /* kubernetes service traffic requiring SNAT */ mark match 0x4000/0x4000 random-fully

Chain KUBE-PROXY-CANARY (0 references)
 pkts bytes target     prot opt in     out     source               destination

Chain KUBE-SEP-5EZNUB76DNDU3ZTK (1 references)
 pkts bytes target     prot opt in     out     source               destination
    0     0 KUBE-MARK-MASQ  all  --  *      *       172.18.0.3           0.0.0.0/0            /* kube-system/kube-dns:dns */
    0     0 DNAT       udp  --  *      *       0.0.0.0/0            0.0.0.0/0            /* kube-system/kube-dns:dns */ udp to:172.18.0.3:53

Chain KUBE-SEP-FBR7GW7VHBPLDP7B (1 references)
 pkts bytes target     prot opt in     out     source               destination
    0     0 KUBE-MARK-MASQ  all  --  *      *       172.18.0.3           0.0.0.0/0            /* kube-system/kube-dns:metrics */
    0     0 DNAT       tcp  --  *      *       0.0.0.0/0            0.0.0.0/0            /* kube-system/kube-dns:metrics */ tcp to:172.18.0.3:9153

Chain KUBE-SEP-KLMOTHZKN3LNJ7NB (1 references)
 pkts bytes target     prot opt in     out     source               destination
    0     0 KUBE-MARK-MASQ  all  --  *      *       172.18.0.2           0.0.0.0/0            /* kube-system/kube-dns:dns */
    0     0 DNAT       udp  --  *      *       0.0.0.0/0            0.0.0.0/0            /* kube-system/kube-dns:dns */ udp to:172.18.0.2:53

Chain KUBE-SEP-PATXOTJBHFPU4CNS (1 references)
 pkts bytes target     prot opt in     out     source               destination
    0     0 KUBE-MARK-MASQ  all  --  *      *       172.17.0.2           0.0.0.0/0            /* default/kubernetes:https */
    0     0 DNAT       tcp  --  *      *       0.0.0.0/0            0.0.0.0/0            /* default/kubernetes:https */ tcp to:172.17.0.2:8443

Chain KUBE-SEP-PXI5DVWAQX37NI6K (1 references)
 pkts bytes target     prot opt in     out     source               destination
    0     0 KUBE-MARK-MASQ  all  --  *      *       172.18.0.5           0.0.0.0/0            /* default/web-svc-cip: */
    0     0 DNAT       tcp  --  *      *       0.0.0.0/0            0.0.0.0/0            /* default/web-svc-cip: */ tcp to:172.18.0.5:8000

Chain KUBE-SEP-QBJZSVSYALF66SO6 (1 references)
 pkts bytes target     prot opt in     out     source               destination
    0     0 KUBE-MARK-MASQ  all  --  *      *       172.18.0.4           0.0.0.0/0            /* default/web-svc-cip: */
    0     0 DNAT       tcp  --  *      *       0.0.0.0/0            0.0.0.0/0            /* default/web-svc-cip: */ tcp to:172.18.0.4:8000

Chain KUBE-SEP-RYTAWN2VNC6HJFUQ (1 references)
 pkts bytes target     prot opt in     out     source               destination
    0     0 KUBE-MARK-MASQ  all  --  *      *       172.18.0.3           0.0.0.0/0            /* kube-system/kube-dns:dns-tcp */
    0     0 DNAT       tcp  --  *      *       0.0.0.0/0            0.0.0.0/0            /* kube-system/kube-dns:dns-tcp */ tcp to:172.18.0.3:53

Chain KUBE-SEP-S77W6PMQVTFQMRF2 (1 references)
 pkts bytes target     prot opt in     out     source               destination
    0     0 KUBE-MARK-MASQ  all  --  *      *       172.18.0.2           0.0.0.0/0            /* kube-system/kube-dns:dns-tcp */
    0     0 DNAT       tcp  --  *      *       0.0.0.0/0            0.0.0.0/0            /* kube-system/kube-dns:dns-tcp */ tcp to:172.18.0.2:53

Chain KUBE-SEP-SZWO3ZNWGEEQBN7C (1 references)
 pkts bytes target     prot opt in     out     source               destination
    0     0 KUBE-MARK-MASQ  all  --  *      *       172.18.0.6           0.0.0.0/0            /* default/web-svc-cip: */
    0     0 DNAT       tcp  --  *      *       0.0.0.0/0            0.0.0.0/0            /* default/web-svc-cip: */ tcp to:172.18.0.6:8000

Chain KUBE-SEP-Z2QZYSORHBODDMUQ (1 references)
 pkts bytes target     prot opt in     out     source               destination
    0     0 KUBE-MARK-MASQ  all  --  *      *       172.18.0.2           0.0.0.0/0            /* kube-system/kube-dns:metrics */
    0     0 DNAT       tcp  --  *      *       0.0.0.0/0            0.0.0.0/0            /* kube-system/kube-dns:metrics */ tcp to:172.18.0.2:9153

Chain KUBE-SERVICES (2 references)
 pkts bytes target     prot opt in     out     source               destination
    0     0 KUBE-MARK-MASQ  tcp  --  *      *      !10.244.0.0/16        10.96.0.1            /* default/kubernetes:https cluster IP */ tcp dpt:443
    0     0 KUBE-SVC-NPX46M4PTMTKRN6Y  tcp  --  *      *       0.0.0.0/0            10.96.0.1            /* default/kubernetes:https cluster IP */ tcp dpt:443
    0     0 KUBE-MARK-MASQ  udp  --  *      *      !10.244.0.0/16        10.96.0.10           /* kube-system/kube-dns:dns cluster IP */ udp dpt:53
    0     0 KUBE-SVC-TCOU7JCQXEZGVUNU  udp  --  *      *       0.0.0.0/0            10.96.0.10           /* kube-system/kube-dns:dns cluster IP */ udp dpt:53
    0     0 KUBE-MARK-MASQ  tcp  --  *      *      !10.244.0.0/16        10.96.0.10           /* kube-system/kube-dns:dns-tcp cluster IP */ tcp dpt:53
    0     0 KUBE-SVC-ERIFXISQEP7F7OF4  tcp  --  *      *       0.0.0.0/0            10.96.0.10           /* kube-system/kube-dns:dns-tcp cluster IP */ tcp dpt:53
    0     0 KUBE-MARK-MASQ  tcp  --  *      *      !10.244.0.0/16        10.96.0.10           /* kube-system/kube-dns:metrics cluster IP */ tcp dpt:9153
    0     0 KUBE-SVC-JD5MR3NA4I4DYORP  tcp  --  *      *       0.0.0.0/0            10.96.0.10           /* kube-system/kube-dns:metrics cluster IP */ tcp dpt:9153
    0     0 KUBE-MARK-MASQ  tcp  --  *      *      !10.244.0.0/16        10.97.60.103         /* default/web-svc-cip: cluster IP */ tcp dpt:80
    0     0 KUBE-SVC-WKCOG6KH24K26XRJ  tcp  --  *      *       0.0.0.0/0            10.97.60.103         /* default/web-svc-cip: cluster IP */ tcp dpt:80
  127  7620 KUBE-NODEPORTS  all  --  *      *       0.0.0.0/0            0.0.0.0/0            /* kubernetes service nodeports; NOTE: this must be the last rule in this chain */ ADDRTYPE match dst-type LOCAL

Chain KUBE-SVC-ERIFXISQEP7F7OF4 (1 references)
 pkts bytes target     prot opt in     out     source               destination
    0     0 KUBE-SEP-S77W6PMQVTFQMRF2  all  --  *      *       0.0.0.0/0            0.0.0.0/0            /* kube-system/kube-dns:dns-tcp */ statistic mode random probability 0.50000000000
    0     0 KUBE-SEP-RYTAWN2VNC6HJFUQ  all  --  *      *       0.0.0.0/0            0.0.0.0/0            /* kube-system/kube-dns:dns-tcp */

Chain KUBE-SVC-JD5MR3NA4I4DYORP (1 references)
 pkts bytes target     prot opt in     out     source               destination
    0     0 KUBE-SEP-Z2QZYSORHBODDMUQ  all  --  *      *       0.0.0.0/0            0.0.0.0/0            /* kube-system/kube-dns:metrics */ statistic mode random probability 0.50000000000
    0     0 KUBE-SEP-FBR7GW7VHBPLDP7B  all  --  *      *       0.0.0.0/0            0.0.0.0/0            /* kube-system/kube-dns:metrics */

Chain KUBE-SVC-NPX46M4PTMTKRN6Y (1 references)
 pkts bytes target     prot opt in     out     source               destination
    0     0 KUBE-SEP-PATXOTJBHFPU4CNS  all  --  *      *       0.0.0.0/0            0.0.0.0/0            /* default/kubernetes:https */

Chain KUBE-SVC-TCOU7JCQXEZGVUNU (1 references)
 pkts bytes target     prot opt in     out     source               destination
    0     0 KUBE-SEP-KLMOTHZKN3LNJ7NB  all  --  *      *       0.0.0.0/0            0.0.0.0/0            /* kube-system/kube-dns:dns */ statistic mode random probability 0.50000000000
    0     0 KUBE-SEP-5EZNUB76DNDU3ZTK  all  --  *      *       0.0.0.0/0            0.0.0.0/0            /* kube-system/kube-dns:dns */

Chain KUBE-SVC-WKCOG6KH24K26XRJ (1 references)
 pkts bytes target     prot opt in     out     source               destination
    0     0 KUBE-SEP-QBJZSVSYALF66SO6  all  --  *      *       0.0.0.0/0            0.0.0.0/0            /* default/web-svc-cip: */ statistic mode random probability 0.33333333349
    0     0 KUBE-SEP-PXI5DVWAQX37NI6K  all  --  *      *       0.0.0.0/0            0.0.0.0/0            /* default/web-svc-cip: */ statistic mode random probability 0.50000000000
    0     0 KUBE-SEP-SZWO3ZNWGEEQBN7C  all  --  *      *       0.0.0.0/0            0.0.0.0/0            /* default/web-svc-cip: */
```

- Нужное правило находится в цепочке KUBE-SERVICES

```console
Chain KUBE-SERVICES (2 references)
 pkts bytes target     prot opt in     out     source               destination
    0     0 KUBE-MARK-MASQ  tcp  --  *      *      !10.244.0.0/16        10.97.60.103         /* default/web-svc-cip: cluster IP */ tcp dpt:80
    0     0 KUBE-SVC-WKCOG6KH24K26XRJ  tcp  --  *      *       0.0.0.0/0            10.97.60.103         /* default/web-svc-cip: cluster IP */ tcp dpt:80
````

- Затем мы переходим в цепочку KUBE-SVC-..... - здесь находятся правила "балансировки" между цепочками KUBESEP-..... (SVC - очевидно Service)

```console
Chain KUBE-SVC-WKCOG6KH24K26XRJ (1 references)
 pkts bytes target     prot opt in     out     source               destination
    0     0 KUBE-SEP-QBJZSVSYALF66SO6  all  --  *      *       0.0.0.0/0            0.0.0.0/0            /* default/web-svc-cip: */ statistic mode random probability 0.33333333349
    0     0 KUBE-SEP-PXI5DVWAQX37NI6K  all  --  *      *       0.0.0.0/0            0.0.0.0/0            /* default/web-svc-cip: */ statistic mode random probability 0.50000000000
    0     0 KUBE-SEP-SZWO3ZNWGEEQBN7C  all  --  *      *       0.0.0.0/0            0.0.0.0/0            /* default/web-svc-cip: */
```

- В цепочках KUBE-SEP-..... находятся конкретные правила перенаправления трафика (через DNAT) (SEP - Service Endpoint)

```console

Chain KUBE-SEP-PXI5DVWAQX37NI6K (1 references)
 pkts bytes target     prot opt in     out     source               destination
    0     0 KUBE-MARK-MASQ  all  --  *      *       172.18.0.5           0.0.0.0/0            /* default/web-svc-cip: */
    0     0 DNAT       tcp  --  *      *       0.0.0.0/0            0.0.0.0/0            /* default/web-svc-cip: */ tcp to:172.18.0.5:8000

Chain KUBE-SEP-QBJZSVSYALF66SO6 (1 references)
 pkts bytes target     prot opt in     out     source               destination
    0     0 KUBE-MARK-MASQ  all  --  *      *       172.18.0.4           0.0.0.0/0            /* default/web-svc-cip: */
    0     0 DNAT       tcp  --  *      *       0.0.0.0/0            0.0.0.0/0            /* default/web-svc-cip: */ tcp to:172.18.0.4:8000

Chain KUBE-SEP-SZWO3ZNWGEEQBN7C (1 references)
 pkts bytes target     prot opt in     out     source               destination
    0     0 KUBE-MARK-MASQ  all  --  *      *       172.18.0.6           0.0.0.0/0            /* default/web-svc-cip: */
    0     0 DNAT       tcp  --  *      *       0.0.0.0/0            0.0.0.0/0            /* default/web-svc-cip: */ tcp to:172.18.0.6:8000
```

> Подробное описание можно почитать [тут](https://msazure.club/kubernetes-services-and-iptables/)

### Включение IPVS

Итак, с версии 1.0.0 Minikube поддерживает работу kubeproxy в режиме IPVS. Попробуем включить его "наживую".

> При запуске нового инстанса Minikube лучше использовать ключ **--extra-config** и сразу указать, что мы хотим IPVS: **minikube start --extra-config=kube-proxy.mode="ipvs"**

- Включим IPVS для kube-proxy, исправив ConfigMap (конфигурация Pod, хранящаяся в кластере)
  - Выполним команду **kubectl --namespace kube-system edit configmap/kube-proxy**
  - Или minikube dashboard (далее надо выбрать namespace kube-system, Configs and Storage/Config Maps)
- Теперь найдем в файле конфигурации kube-proxy строку **mode: ""**
- Изменим значение **mode** с пустого на **ipvs** и добавим параметр **strictARP: true** и сохраним изменения

```yml
ipvs:
  strictARP: true
mode: "ipvs"
```

- Теперь удалим Pod с kube-proxy, чтобы применить новую конфигурацию (он входит в DaemonSet и будет запущен автоматически)

```console
kubectl --namespace kube-system delete pod --selector='k8s-app=kube-proxy'
pod "kube-proxy-7cwgh" deleted
```

> Описание работы и настройки [IPVS в K8S](https://github.com/kubernetes/kubernetes/blob/master/pkg/proxy/ipvs/README.md)  
> Причины включения strictARP описаны [тут](https://github.com/metallb/metallb/issues/153)

- После успешного рестарта kube-proxy выполним команду minikube ssh и проверим, что получилось
- Выполним команду **iptables --list -nv -t nat** в ВМ Minikube
- Что-то поменялось, но старые цепочки на месте (хотя у них теперь 0 references) �
  - kube-proxy настроил все по-новому, но не удалил мусор
  - Запуск kube-proxy --cleanup в нужном поде - тоже не помогает

```console
kubectl --namespace kube-system exec kube-proxy-<POD> kube-proxy --cleanup

W0520 09:57:48.045293     606 server.go:225] WARNING: all flags other than --config, --write-config-to, and --cleanup are deprecated. Please begin using a config file ASAP.
```

Полностью очистим все правила iptables:

- Создадим в ВМ с Minikube файл /tmp/iptables.cleanup

```console
*nat
-A POSTROUTING -s 172.17.0.0/16 ! -o docker0 -j MASQUERADE
COMMIT
*filter
COMMIT
*mangle
COMMIT
```

- Применим конфигурацию: iptables-restore /tmp/iptables.cleanup

```console
iptables-restore /tmp/iptables.cleanup
```

- Теперь надо подождать (примерно 30 секунд), пока kube-proxy восстановит правила для сервисов
- Проверим результат iptables --list -nv -t nat

```console
iptables --list -nv -t nat

Chain PREROUTING (policy ACCEPT 0 packets, 0 bytes)
 pkts bytes target     prot opt in     out     source               destination
    0     0 KUBE-SERVICES  all  --  *      *       0.0.0.0/0            0.0.0.0/0            /* kubernetes service portals */

Chain INPUT (policy ACCEPT 0 packets, 0 bytes)
 pkts bytes target     prot opt in     out     source               destination

Chain OUTPUT (policy ACCEPT 9 packets, 540 bytes)
 pkts bytes target     prot opt in     out     source               destination
   62  3720 KUBE-SERVICES  all  --  *      *       0.0.0.0/0            0.0.0.0/0            /* kubernetes service portals */

Chain POSTROUTING (policy ACCEPT 2 packets, 120 bytes)
 pkts bytes target     prot opt in     out     source               destination
   61  3660 KUBE-POSTROUTING  all  --  *      *       0.0.0.0/0            0.0.0.0/0            /* kubernetes postrouting rules */
    7   420 MASQUERADE  all  --  *      !docker0  172.17.0.0/16        0.0.0.0/0
   66  3960 KIND-MASQ-AGENT  all  --  *      *       0.0.0.0/0            0.0.0.0/0            ADDRTYPE match dst-type !LOCAL /* kind-masq-agent: ensure nat POSTROUTING directs all non-LOCAL destination traffic to our custom KIND-MASQ-AGENT chain */

Chain KIND-MASQ-AGENT (1 references)
 pkts bytes target     prot opt in     out     source               destination
    0     0 RETURN     all  --  *      *       0.0.0.0/0            10.244.0.0/16        /* kind-masq-agent: local traffic is not subject to MASQUERADE */
   66  3960 MASQUERADE  all  --  *      *       0.0.0.0/0            0.0.0.0/0            /* kind-masq-agent: outbound traffic is subject to MASQUERADE (must be last in chain) */

Chain KUBE-FIREWALL (0 references)
 pkts bytes target     prot opt in     out     source               destination
    0     0 KUBE-MARK-DROP  all  --  *      *       0.0.0.0/0            0.0.0.0/0

Chain KUBE-KUBELET-CANARY (0 references)
 pkts bytes target     prot opt in     out     source               destination

Chain KUBE-LOAD-BALANCER (0 references)
 pkts bytes target     prot opt in     out     source               destination
    0     0 KUBE-MARK-MASQ  all  --  *      *       0.0.0.0/0            0.0.0.0/0

Chain KUBE-MARK-DROP (1 references)
 pkts bytes target     prot opt in     out     source               destination

Chain KUBE-MARK-MASQ (2 references)
 pkts bytes target     prot opt in     out     source               destination
    0     0 MARK       all  --  *      *       0.0.0.0/0            0.0.0.0/0            MARK or 0x4000

Chain KUBE-NODE-PORT (1 references)
 pkts bytes target     prot opt in     out     source               destination

Chain KUBE-POSTROUTING (1 references)
 pkts bytes target     prot opt in     out     source               destination
    0     0 MASQUERADE  all  --  *      *       0.0.0.0/0            0.0.0.0/0            /* kubernetes service traffic requiring SNAT */ mark match 0x4000/0x4000 random-fully
    0     0 MASQUERADE  all  --  *      *       0.0.0.0/0            0.0.0.0/0            /* Kubernetes endpoints dst ip:port, source ip for solving hairpin purpose */ match-set KUBE-LOOP-BACK dst,dst,src

Chain KUBE-SERVICES (2 references)
 pkts bytes target     prot opt in     out     source               destination
    0     0 KUBE-MARK-MASQ  all  --  *      *      !10.244.0.0/16        0.0.0.0/0            /* Kubernetes service cluster ip + port for masquerade purpose */ match-set KUBE-CLUSTER-IP dst,dst
    6   360 KUBE-NODE-PORT  all  --  *      *       0.0.0.0/0            0.0.0.0/0            ADDRTYPE match dst-type LOCAL
    0     0 ACCEPT     all  --  *      *       0.0.0.0/0            0.0.0.0/0            match-set KUBE-CLUSTER-IP dst,dst
```

- Итак, лишние правила удалены и мы видим только актуальную конфигурацию
  - kube-proxy периодически делает полную синхронизацию правил в своих цепочках)
- Как посмотреть конфигурацию IPVS? Ведь в ВМ нет утилиты ipvsadm ?
  - В ВМ выполним команду toolbox - в результате мы окажется в контейнере с Fedora
  - Теперь установим ipvsadm: dnf install -y ipvsadm && dnf clean all

Выполним ipvsadm --list -n и среди прочих сервисов найдем наш:

```console
ipvsadm --list -n

IP Virtual Server version 1.2.1 (size=4096)
Prot LocalAddress:Port Scheduler Flags
  -> RemoteAddress:Port           Forward Weight ActiveConn InActConn
TCP  10.97.60.103:80 rr
  -> 172.18.0.4:8000              Masq    1      0          0
  -> 172.18.0.5:8000              Masq    1      0          0
  -> 172.18.0.6:8000              Masq    1      0          0
```

- Теперь выйдем из контейнера toolbox и сделаем ping кластерного IP:

```console
ping 10.97.60.103

PING 10.97.60.103 (10.97.60.103) 56(84) bytes of data.
64 bytes from 10.97.60.103: icmp_seq=1 ttl=64 time=0.030 ms
64 bytes from 10.97.60.103: icmp_seq=2 ttl=64 time=0.077 ms
64 bytes from 10.97.60.103: icmp_seq=3 ttl=64 time=0.038 ms
64 bytes from 10.97.60.103: icmp_seq=4 ttl=64 time=0.064 ms
```

Итак, все работает. Но почему пингуется виртуальный IP?

Все просто - он уже не такой виртуальный. Этот IP теперь есть на интерфейсе kube-ipvs0:

```console
ip addr show kube-ipvs0
17: kube-ipvs0: <BROADCAST,NOARP> mtu 1500 qdisc noop state DOWN group default
    link/ether a6:de:ae:75:df:04 brd ff:ff:ff:ff:ff:ff
    inet 10.97.60.103/32 brd 10.97.60.103 scope global kube-ipvs0
       valid_lft forever preferred_lft forever
```

> Также, правила в iptables построены по-другому. Вместо цепочки правил для каждого сервиса, теперь используются хэш-таблицы (ipset). Можем посмотреть их, установив утилиту ipset в toolbox .

```console
ipset list

Name: KUBE-LOOP-BACK
Type: hash:ip,port,ip
Revision: 5
Header: family inet hashsize 1024 maxelem 65536
Size in memory: 816
References: 1
Number of entries: 9
Members:
172.18.0.4,6:8000,172.18.0.4
172.18.0.5,6:8000,172.18.0.5
172.18.0.6,6:8000,172.18.0.6

Name: KUBE-CLUSTER-IP
Type: hash:ip,port
Revision: 5
Header: family inet hashsize 1024 maxelem 65536
Size in memory: 408
References: 2
Number of entries: 5
Members:
10.97.60.103,6:80
```

### Работа с LoadBalancer и Ingress - Установка MetalLB

MetalLB позволяет запустить внутри кластера L4-балансировщик, который будет принимать извне запросы к сервисам и раскидывать их между подами. Установка его проста:

```console
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.9.3/manifests/namespace.yaml
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.9.3/manifests/metallb.yaml
kubectl create secret generic -n metallb-system memberlist --from-literal=secretkey="$(openssl rand -base64 128)"
```

> ❗ В продуктиве так делать не надо. Сначала стоит скачать файл и разобраться, что там внутри

Проверим, что были созданы нужные объекты:

```console
kubectl --namespace metallb-system get all

NAME                              READY   STATUS    RESTARTS   AGE
pod/controller-5468756d88-nxh2f   1/1     Running   0          19s
pod/speaker-rkb5s                 1/1     Running   0          19s

NAME                     DESIRED   CURRENT   READY   UP-TO-DATE   AVAILABLE   NODE SELECTOR                 AGE
daemonset.apps/speaker   1         1         1       1            1           beta.kubernetes.io/os=linux   19s

NAME                         READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/controller   1/1     1            1           19s

NAME                                    DESIRED   CURRENT   READY   AGE
replicaset.apps/controller-5468756d88   1         1         1       19s
```

Теперь настроим балансировщик с помощью ConfigMap

- Создадмс манифест metallb-config.yaml в папке kubernetes-networks:

```yml
apiVersion: v1
kind: ConfigMap
metadata:
  namespace: metallb-system
  name: config
data:
  config: |
    address-pools:
      - name: default
        protocol: layer2
        addresses:
          - "172.17.255.1-172.17.255.255"
```

- В конфигурации мы настраиваем:
  - Режим L2 (анонс адресов балансировщиков с помощью ARP)
  - Создаем пул адресов 172.17.255.1-172.17.255.255 - они будут назначаться сервисам с типом LoadBalancer
- Теперь можно применить наш манифест: kubectl apply -f metallb-config.yaml
- Контроллер подхватит изменения автоматически

```console
kubectl apply -f metallb-config.yaml
configmap/config created
```

### MetalLB | Проверка конфигурации

Сделаем копию файла web-svc-cip.yaml в web-svclb.yaml и откроем его в редакторе:

```yml
apiVersion: v1
kind: Service
metadata:
  name: web-svc-lb
spec:
  selector:
    app: web
  type: LoadBalancer
  ports:
    - protocol: TCP
      port: 80
      targetPort: 8000
```

- Применим манифест

```console
kubectl apply -f web-svc-lb.yaml
service/web-svc-lb created
```

- Теперь посмотрим логи пода-контроллера MetalLB

```console
kubectl --namespace metallb-system logs pod/controller-5468756d88-flqbf

{"caller":"service.go:98","event":"ipAllocated","ip":"172.17.255.1","msg":"IP address assigned by controller","service":"default/web-svc-lb","ts":"2020-05-21T19:38:21.161120726Z"}
```

Обратим внимание на назначенный IP-адрес (или посмотрим его в выводе kubectl describe svc websvc-lb)

```console
kubectl describe svc web-svc-lb

Name:                     web-svc-lb
Namespace:                default
Labels:                   <none>
Annotations:              kubectl.kubernetes.io/last-applied-configuration:
                            {"apiVersion":"v1","kind":"Service","metadata":{"annotations":{},"name":"web-svc-lb","namespace":"default"},"spec":{"ports":[{"port":80,"p...
Selector:                 app=web
Type:                     LoadBalancer
IP:                       10.103.160.42
LoadBalancer Ingress:     172.17.255.1
Port:                     <unset>  80/TCP
TargetPort:               8000/TCP
NodePort:                 <unset>  32615/TCP
Endpoints:                172.17.0.5:8000,172.17.0.6:8000,172.17.0.7:8000
Session Affinity:         None
External Traffic Policy:  Cluster
Events:
  Type    Reason       Age   From                Message
  ----    ------       ----  ----                -------
  Normal  IPAllocated  106s  metallb-controller  Assigned IP "172.17.255.1"
````

- Если мы попробуем открыть URL <http://172.17.255.1/index.html>, то... ничего не выйдет.

- Это потому, что сеть кластера изолирована от нашей основной ОС (а ОС не знает ничего о подсети для балансировщиков)
- Чтобы это поправить, добавим статический маршрут:
  - В реальном окружении это решается добавлением нужной подсети на интерфейс сетевого оборудования
  - Или использованием L3-режима (что потребует усилий от сетевиков, но более предпочтительно)

- Найдем IP-адрес виртуалки с Minikube. Например так:

```console
minikube ssh

ip addr show eth0
42: eth0@if43: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue state UP group default
    link/ether 02:42:ac:11:00:02 brd ff:ff:ff:ff:ff:ff link-netnsid 0
    inet 172.17.0.2/16 brd 172.17.255.255 scope global eth0
       valid_lft forever preferred_lft forever
````

- Добавим маршрут в вашей ОС на IP-адрес Minikube:

```console
sudo route add 172.17.255.0/24 172.17.0.2
```

DISCLAIMER:

Добавление маршрута может иметь другой синтаксис (например, ip route add 172.17.255.0/24 via 192.168.64.4 в ОС Linux) или вообще не сработать (в зависимости от VM Driver в Minkube).

В этом случае, не надо расстраиваться - работу наших сервисов и манифестов можно проверить из консоли Minikube, просто будет не так эффектно.

> P.S. - Самый простой способ найти IP виртуалки с minikube - minikube ip

Все получилось, можно открыть в браузере URL с IP-адресом нашего балансировщика и посмотреть, как космические корабли бороздят просторы вселенной.

Если пообновлять страничку с помощью Ctrl-F5 (т.е. игнорируя кэш), то будет видно, что каждый наш запрос приходит на другой под. Причем, порядок смены подов - всегда один и тот же.

Так работает IPVS - по умолчанию он использует **rr** (Round-Robin) балансировку.

К сожалению, выбрать алгоритм на уровне манифеста сервиса нельзя. Но когда-нибудь, эта полезная фича [появится](https://kubernetes.io/blog/2018/07/09/ipvs-based-in-cluster-load-balancing-deep-dive/).

> Доступные алгоритмы балансировки описаны [здесь](https://github.com/kubernetes/kubernetes/blob/1cb3b5807ec37490b4582f22d991c043cc468195/pkg/proxy/apis/config/types.go#L185) и появится [здесь](http://www.linuxvirtualserver.org/docs/scheduling.html).

### Задание со ⭐ | DNS через MetalLB

- Сделаем сервис LoadBalancer, который откроет доступ к CoreDNS снаружи кластера (позволит получать записи через внешний IP). Например, nslookup web.default.cluster.local 172.17.255.10.
- Поскольку DNS работает по TCP и UDP протоколам - учтем это в конфигурации. Оба протокола должны работать по одному и тому же IP-адресу балансировщика.
- Полученные манифесты положим в подкаталог ./coredns

> 😉 [Hint](https://metallb.universe.tf/usage/)

Для выполнения задания создадим манифест с двумя сервисами типа LB включающие размещение на общем IP:

- аннотацию **metallb.universe.tf/allow-shared-ip** равную для обоих сервисов
- spec.loadBalancerIP равный для обоих сервисов

coredns-svc-lb.yaml

```yml
apiVersion: v1
kind: Service
metadata:
  name: coredns-svc-lb-tcp
  annotations:
    metallb.universe.tf/allow-shared-ip: coredns
spec:
  loadBalancerIP: 172.17.255.2
  selector:
    k8s-app: kube-dns
  type: LoadBalancer
  ports:
    - protocol: TCP
      port: 53
      targetPort: 53
---
apiVersion: v1
kind: Service
metadata:
  name: coredns-svc-lb-udp
  annotations:
    metallb.universe.tf/allow-shared-ip: coredns
spec:
  loadBalancerIP: 172.17.255.2
  selector:
    k8s-app: kube-dns
  type: LoadBalancer
  ports:
    - protocol: UDP
      port: 53
      targetPort: 53
```

Применим манифест:

```console
kubectl apply -f coredns-svc-lb.yaml -n kube-system
service/coredns-svc-lb-tcp created
service/coredns-svc-lb-udp created
```

Проверим, что сервисы создались:

```console
kubectl get svc -n kube-system | grep coredns-svc
coredns-svc-lb-tcp   LoadBalancer   10.111.58.253   172.17.255.2   53:31250/TCP             90s
coredns-svc-lb-udp   LoadBalancer   10.96.243.226   172.17.255.2   53:32442/UDP             89s
```

Обратимся к DNS:

```console
nslookup web-svc-cip.default.svc.cluster.local 172.17.255.2

Server:         172.17.255.2
Address:        172.17.255.2#53

Name:   web-svc-cip.default.svc.cluster.local
Address: 10.104.155.78
```

### Создание Ingress

Теперь, когда у нас есть балансировщик, можно заняться Ingress-контроллером и прокси:

- неудобно, когда на каждый Web-сервис надо выделять свой IP-адрес
- а еще хочется балансировку по HTTP-заголовкам (sticky sessions)

Для нашего домашнего задания возьмем почти "коробочный" **ingress-nginx** от проекта Kubernetes. Это "достаточно хороший" Ingress для умеренных нагрузок, основанный на OpenResty и пачке Lua-скриптов.

- Установка начинается с основного манифеста:

```console
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingressnginx/master/deploy/static/provider/cloud/deploy.yaml

namespace/ingress-nginx created
configmap/nginx-configuration created
configmap/tcp-services created
configmap/udp-services created
serviceaccount/nginx-ingress-serviceaccount created
clusterrole.rbac.authorization.k8s.io/nginx-ingress-clusterrole created
role.rbac.authorization.k8s.io/nginx-ingress-role created
rolebinding.rbac.authorization.k8s.io/nginx-ingress-role-nisa-binding created
clusterrolebinding.rbac.authorization.k8s.io/nginx-ingress-clusterrole-nisa-binding created
deployment.apps/nginx-ingress-controller created
limitrange/ingress-nginx created
```

- После установки основных компонентов, в [инструкции](https://kubernetes.github.io/ingress-nginx/deploy/#bare-metal) рекомендуется применить манифест, который создаст NodePort -сервис. Но у нас есть MetalLB, мы можем сделать круче.

> Можно сделать просто minikube addons enable ingress , но мы не ищем легких путей

Проверим, что контроллер запустился:

```console
kubectl get pods -n ingress-nginx
NAME                                        READY   STATUS    RESTARTS   AGE
nginx-ingress-controller-5bb8fb4bb6-rvkz5   1/1     Running   0          2m2s
```

Создадим файл nginx-lb.yaml c конфигурацией LoadBalancer - сервиса (работаем в каталоге kubernetes-networks):

```yml
kind: Service
apiVersion: v1
metadata:
  name: ingress-nginx
  namespace: ingress-nginx
  labels:
    app.kubernetes.io/name: ingress-nginx
    app.kubernetes.io/part-of: ingress-nginx
spec:
  externalTrafficPolicy: Local
  type: LoadBalancer
  selector:
    app.kubernetes.io/name: ingress-nginx
    app.kubernetes.io/part-of: ingress-nginx
  ports:
    - name: http
      port: 80
      targetPort: http
    - name: https
      port: 443
      targetPort: https
```

- Теперь применим созданный манифест и посмотрим на IP-адрес, назначенный ему MetalLB

```console
kubectl get svc -n ingress-nginx

NAME            TYPE           CLUSTER-IP     EXTERNAL-IP    PORT(S)                      AGE
ingress-nginx   LoadBalancer   10.109.249.5   172.17.255.3   80:30552/TCP,443:30032/TCP   5m13s
```

- Теперь можно сделать пинг на этот IP-адрес и даже curl

```console
curl 172.17.255.3
<html>
<head><title>404 Not Found</title></head>
<body>
<center><h1>404 Not Found</h1></center>
<hr><center>nginx/1.17.8</center>
</body>
</html>
```

Видим страничку 404 от Nginx - значит работает!

### Подключение приложение Web к Ingress

- Наш Ingress-контроллер не требует **ClusterIP** для балансировки трафика
- Список узлов для балансировки заполняется из ресурса Endpoints нужного сервиса (это нужно для "интеллектуальной" балансировки, привязки сессий и т.п.)
- Поэтому мы можем использовать **headless-сервис** для нашего вебприложения.
- Скопируем web-svc-cip.yaml в web-svc-headless.yaml
  - Изменим имя сервиса на **web-svc**
  - Добавим параметр **clusterIP: None**

```yml
apiVersion: v1
kind: Service
metadata:
  name: web-svc
spec:
  selector:
    app: web
  type: ClusterIP
  clusterIP: None
  ports:
    - protocol: TCP
      port: 80
      targetPort: 8000
```

- Теперь применим полученный манифест и проверим, что ClusterIP для сервиса web-svc действительно не назначен

```console
kubectl apply -f web-svc-headless.yaml
service/web-svc created

kubectl get svc
NAME          TYPE           CLUSTER-IP      EXTERNAL-IP    PORT(S)        AGE
web-svc       ClusterIP      None            <none>         80/TCP         32s
```

### Создание правил Ingress

Теперь настроим наш ingress-прокси, создав манифест с ресурсом Ingress (файл назовем web-ingress.yaml):

```yml
apiVersion: networking.k8s.io/v1beta1
kind: Ingress
metadata:
  name: web
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
spec:
  rules:
  - http:
      paths:
      - path: /web
        backend:
          serviceName: web-svc
          servicePort: 8000
```

Применим манифест и проверим, что корректно заполнены Address и Backends:

```console
kubectl apply -f web-ingress.yaml
ingress.networking.k8s.io/web created

kubectl describe ingress/web
Name:             web
Namespace:        default
Address:          172.17.255.3
Default backend:  default-http-backend:80 (<none>)
Rules:
  Host  Path  Backends
  ----  ----  --------
  *
        /web   web-svc:8000 (172.17.0.5:8000,172.17.0.6:8000,172.17.0.7:8000)
Annotations:
  kubectl.kubernetes.io/last-applied-configuration:  {"apiVersion":"networking.k8s.io/v1beta1","kind":"Ingress","metadata":{"annotations":{"nginx.ingress.kubernetes.io/rewrite-target":"/"},"name":"web","namespace":"default"},"spec":{"rules":[{"http":{"paths":[{"backend":{"serviceName":"web-svc","servicePort":8000},"path":"/web"}]}}]}}

  nginx.ingress.kubernetes.io/rewrite-target:  /
Events:
  Type    Reason  Age   From                      Message
  ----    ------  ----  ----                      -------
  Normal  CREATE  24s   nginx-ingress-controller  Ingress default/web
  Normal  UPDATE  4s    nginx-ingress-controller  Ingress default/web
```

- Теперь можно проверить, что страничка доступна в браузере (<http://172.17.255.3/web/index.html)>
- Обратим внимание, что обращения к странице тоже балансируются между Podами. Только сейчас это происходит средствами nginx, а не IPVS

### Задания со ⭐ | Ingress для Dashboard

Добавим доступ к kubernetes-dashboard через наш Ingress-прокси:

- Cервис должен быть доступен через префикс /dashboard.
- Kubernetes Dashboard должен быть развернут из официального манифеста. Актуальная ссылка в [репозитории проекта](https://github.com/kubernetes/dashboard).
- Написанные манифесты положим в подкаталог ./dashboard

```console
kubectl apply -f https://raw.githubusercontent.com/kubernetes/dashboard/v2.0.1/aio/deploy/recommended.yaml
namespace/kubernetes-dashboard created
serviceaccount/kubernetes-dashboard created
service/kubernetes-dashboard created
secret/kubernetes-dashboard-certs created
secret/kubernetes-dashboard-csrf created
secret/kubernetes-dashboard-key-holder created
configmap/kubernetes-dashboard-settings created
role.rbac.authorization.k8s.io/kubernetes-dashboard created
clusterrole.rbac.authorization.k8s.io/kubernetes-dashboard created
rolebinding.rbac.authorization.k8s.io/kubernetes-dashboard created
clusterrolebinding.rbac.authorization.k8s.io/kubernetes-dashboard created
deployment.apps/kubernetes-dashboard created
service/dashboard-metrics-scraper created
deployment.apps/dashboard-metrics-scraper created
```

dashboard-ingress.yaml

```yml
apiVersion: extensions/v1beta1
kind: Ingress
metadata:
  name: dashboard
  annotations:
    nginx.ingress.kubernetes.io/backend-protocol: "HTTPS"
    nginx.ingress.kubernetes.io/rewrite-target: /$2
  namespace: kubernetes-dashboard
spec:
  rules:
  - http:
      paths:
      - path: /dashboard(/|$)(.*)
        backend:
          serviceName: kubernetes-dashboard
          servicePort: 443
```

> Аннотация **nginx.ingress.kubernetes.io/rewrite-target** перезаписывает URL-адрес перед отправкой запроса на бэкэнд подов.  
> В /dashboard(/|$)(.*\) для пути (. \*) хранится динамический URL, который генерируется при доступе к Kubernetes Dashboard.  
> Аннотация **nginx.ingress.kubernetes.io/rewrite-target** заменяет захваченные данные в URL-адресе перед отправкой запроса в сервис kubernetes-dashboard

Применим наш манифест:

```console
kubectl apply -f dashboard-ingress.yaml
ingress.extensions/dashboard configured

kubectl get ingress -n kubernetes-dashboard
NAME        CLASS    HOSTS   ADDRESS        PORTS   AGE
dashboard   <none>   *       172.17.255.3   80      12h
```

Проверим работоспособность по ссылке: <https://172.17.255.3/dashboard/>

### Задания со ⭐ | Canary для Ingress

Реализуем канареечное развертывание с помощью ingress-nginx:

- Перенаправление части трафика на выделенную группу подов должно происходить по HTTP-заголовку.
- Документация [тут](https://github.com/kubernetes/ingress-nginx/blob/master/docs/user-guide/nginx-configuration/annotations.md#canary)
- Естественно, что нам понадобятся 1-2 "канареечных" пода. Написанные манифесты положим в подкаталог ./canary

Пишем манифесты для:

- namespace canary-ns.yaml
- deployment canary-deploy.yaml
- service canary-svc-headless.yaml
- ingress canary-ingress.yml

```yml
apiVersion: networking.k8s.io/v1beta1
kind: Ingress
metadata:
  name: web
  namespace: canary
  annotations:
    kubernetes.io/ingress.class: nginx
    nginx.ingress.kubernetes.io/rewrite-target:  /
    nginx.ingress.kubernetes.io/canary: "true"
    nginx.ingress.kubernetes.io/canary-by-header: "canary"
spec:
  rules:
  - host: app.local
    http:
      paths:
      - path: /web
        backend:
          serviceName: web-svc
          servicePort: 8000
```

И применяем:

```console
kubectl apply -f .
namespace/canary unchanged
deployment.apps/web created
service/web-svc created
ingress.networking.k8s.io/web created
```

> Так же придется впиcать **host: app.local** (к примеру) в манифест web-ingress.yaml  
> иначе на ingress контроллере валится ошибка: **cannot merge alternative backend canary-web-svc-8000 into hostname  that does not exist**

Запоминаем названия pods:

```console
kubectl get pods
NAME                   READY   STATUS    RESTARTS   AGE
web-6596d967d4-fw9px   1/1     Running   0          3h4m
web-6596d967d4-pd65t   1/1     Running   0          3h4m
web-6596d967d4-znkmv   1/1     Running   0          3h4m

kubectl get pods -n canary
NAME                   READY   STATUS    RESTARTS   AGE
web-54c8466885-f8nn6   1/1     Running   0          93m
web-54c8466885-gtk6x   1/1     Running   0          93m
```

И проверяем работу:

```console
curl -s -H "Host: app.local" http://172.17.255.2/web/index.html | grep "HOSTNAME"
export HOSTNAME='web-6596d967d4-fw9px'

curl -s -H "Host: app.local" -H "canary: always" http://172.17.255.2/web/index.html | grep "HOSTNAME"
export HOSTNAME='web-54c8466885-f8nn6'
```

## Security

### task01

- Создадим Service Account **bob** и дади ему роль **admin** в рамках всего кластера

01-serviceAccount.yaml:

```yml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: bob
```

02-clusterRoleBinding.yaml:

```yml
kind: ClusterRoleBinding
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: bob
roleRef:
  kind: ClusterRole
  name: admin
  apiGroup: rbac.authorization.k8s.io
subjects:
- kind: ServiceAccount
  name: bob
  namespace: default
```

- Создадим Service Account **dave** без доступа к кластеру

03-serviceAccount.yaml:

```yml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: dave
```

### task02

- Создадим Namespace prometheus

01-namespace.yaml:

```yml
apiVersion: v1
kind: Namespace
metadata:
  name: prometheus
```

- Создадим Service Account **carol** в этом Namespace

02-serviceAccount.yaml

```yml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: carol
  namespace: prometheus
```

- Дадим всем Service Account в Namespace prometheus возможность делать **get, list, watch** в отношении Pods всего кластера

03-clusterRole.yaml

```yml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: prometheus
rules:
- apiGroups: [""]
  verbs: ["get", "list", "watch"]
  resources: ["pods"]
```

04-clusterRoleBinding.yaml

```yml
kind: ClusterRoleBinding
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: prometheus
roleRef:
  kind: ClusterRole
  name: prometheus
  apiGroup: rbac.authorization.k8s.io
subjects:
- kind: Group
  name: system:serviceaccounts:prometheus
  apiGroup: rbac.authorization.k8s.io
```

### task03

- Создадим Namespace **dev**

01-namespace.yaml

```yml
apiVersion: v1
kind: Namespace
metadata:
  name: dev
```

- Создадим Service Account **jane** в Namespace **dev**

02-serviceAccount.yaml

```yml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: jane
  namespace: dev
```

- Дадим **jane** роль **admin** в рамках Namespace **dev**

03-RoleBinding.yaml

```yml
kind: RoleBinding
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: jane
  namespace: dev
roleRef:
  kind: ClusterRole
  name: admin
  apiGroup: rbac.authorization.k8s.io
subjects:
- kind: ServiceAccount
  name: jane
  namespace: dev
```

- Создади Service Account **ken** в Namespace **dev**

04-serviceAccount.yaml

```yml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: ken
  namespace: dev
```

- Дадим **ken** роль **view** в рамках Namespace **dev**

05-RoleBinding.yaml

```yml
kind: RoleBinding
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: ken
  namespace: dev
roleRef:
  kind: ClusterRole
  name: view
  apiGroup: rbac.authorization.k8s.io
subjects:
- kind: ServiceAccount
  name: ken
  namespace: dev
```

## Kubernetes controllers. ReplicaSet, Deployment, DaemonSet

### Подготовка

Для начала установим Kind и создадим кластер. [Инструкция по быстрому старту](https://kind.sigs.k8s.io/docs/user/quick-start/).

```console
brew install kind
```

Будем использовать следующую конфигурацию нашего локального кластера kind-config.yml

```yml
kind: Cluster
apiVersion: kind.sigs.k8s.io/v1alpha3
nodes:
- role: control-plane
- role: control-plane
- role: control-plane
- role: worker
- role: worker
- role: worker
```

Запустим создание кластера kind:

```console
kind create cluster --config kind-config.yaml

Creating cluster "kind" ...
 ✓ Ensuring node image (kindest/node:v1.18.2) 🖼
 ✓ Preparing nodes 📦 📦 📦 📦 📦 📦  
 ✓ Configuring the external load balancer ⚖️
 ✓ Writing configuration 📜
 ✓ Starting control-plane 🕹️
 ✓ Installing CNI 🔌
 ✓ Installing StorageClass 💾
 ✓ Joining more control-plane nodes 🎮
 ✓ Joining worker nodes 🚜
Set kubectl context to "kind-kind"
You can now use your cluster with:

kubectl cluster-info --context kind-kind
```

После появления отчета об успешном создании убедимся, что развернуто три master ноды и три worker ноды:

```console
kubectl get nodes

NAME                  STATUS   ROLES    AGE     VERSION
kind-control-plane    Ready    master   3m13s   v1.18.2
kind-control-plane2   Ready    master   2m34s   v1.18.2
kind-control-plane3   Ready    master   98s     v1.18.2
kind-worker           Ready    <none>   70s     v1.18.2
kind-worker2          Ready    <none>   71s     v1.18.2
kind-worker3          Ready    <none>   71s     v1.18.2
```

### ReplicaSet

В предыдущем домашнем задании мы запускали standalone pod с микросервисом **frontend**. Пришло время доверить управление pod'ами данного микросервиса одному из контроллеров Kubernetes.

Начнем с ReplicaSet и запустим одну реплику микросервиса frontend.

Создадим и применим манифест frontend-replicaset.yaml

```yml
apiVersion: apps/v1
kind: ReplicaSet
metadata:
  name: frontend
  labels:
    app: frontend
spec:
  replicas: 1
  selector:
    matchLabels:
      app: frontend
  template:
    metadata:
      labels:
        app: frontend
    spec:
      containers:
      - name: server
        image: kovtalex/hipster-frontend:v0.0.2
        env:
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

```console
kubectl apply -f frontend-replicaset.yaml
```

В результате вывод команды **kubectl get pods -l app=frontend** должен показывать, что запущена одна реплика микросервиса **frontend**:

```console
kubectl get pods -l app=frontend

NAME             READY   STATUS    RESTARTS   AGE
frontend-zl2wj   1/1     Running   0          14s
```

Одна работающая реплика - это уже неплохо, но в реальной жизни, как правило, требуется создание нескольких инстансов одного и того же сервиса для:

- Повышения отказоустойчивости
- Распределения нагрузки между репликами

Давайте попробуем увеличить количество реплик сервиса ad-hoc командой:

```console
kubectl scale replicaset frontend --replicas=3
```

Проверить, что ReplicaSet контроллер теперь управляет тремя репликами, и они готовы к работе, можно следующим образом:

```console
kubectl get rs frontend

NAME       DESIRED   CURRENT   READY   AGE
frontend   3         3         3       5m25s
```

Проверим, что благодаря контроллеру pod'ы действительно восстанавливаются после их ручного удаления:

```console
kubectl delete pods -l app=frontend | kubectl get pods -l app=frontend -w

NAME             READY   STATUS    RESTARTS   AGE
frontend-9xvfj   1/1     Running   0          108s
frontend-rgfsf   1/1     Running   0          108s
frontend-zl2wj   1/1     Running   0          3m6s
frontend-9xvfj   1/1     Terminating   0          108s
frontend-rgfsf   1/1     Terminating   0          109s
frontend-zl2wj   1/1     Terminating   0          3m7s
frontend-ptk2f   0/1     Pending       0          0s
frontend-5m7kl   0/1     Pending       0          0s
frontend-ptk2f   0/1     Pending       0          0s
frontend-5m7kl   0/1     Pending       0          0s
frontend-ptk2f   0/1     ContainerCreating   0          0s
frontend-5m7kl   0/1     ContainerCreating   0          0s
frontend-7nzld   0/1     Pending             0          0s
frontend-7nzld   0/1     Pending             0          0s
frontend-7nzld   0/1     ContainerCreating   0          0s
frontend-zl2wj   0/1     Terminating         0          3m7s
frontend-rgfsf   0/1     Terminating         0          110s
frontend-9xvfj   0/1     Terminating         0          110s
frontend-zl2wj   0/1     Terminating         0          3m8s
frontend-zl2wj   0/1     Terminating         0          3m8s
frontend-7nzld   1/1     Running             0          2s
frontend-5m7kl   1/1     Running             0          2s
frontend-9xvfj   0/1     Terminating         0          111s
frontend-9xvfj   0/1     Terminating         0          111s
frontend-ptk2f   1/1     Running             0          2s
frontend-rgfsf   0/1     Terminating         0          2m
frontend-rgfsf   0/1     Terminating         0          2m
```

- Повторно применим манифест frontend-replicaset.yaml
- Убедимся, что количество реплик вновь уменьшилось до одной

```console
kubectl apply -f frontend-replicaset.yaml

kubectl get rs frontend
NAME       DESIRED   CURRENT   READY   AGE
frontend   1         1         1       8m55s
```

- Изменим манифест таким образом, чтобы из манифеста сразу разворачивалось три реплики сервиса, вновь применим его

```console
kubectl apply -f frontend-replicaset.yaml

kubectl get rs frontend
NAME       DESIRED   CURRENT   READY   AGE
frontend   3         3         3       9m44s
```

### Обновление ReplicaSet

Давайте представим, что мы обновили исходный код и хотим выкатить новую версию микросервиса

- Добавим на DockerHub версию образа с новым тегом (**v0.0.2**, можно просто перетегировать старый образ)

```console
docker build -t kovtalex/hipster-frontend:v0.0.2 .
docker push kovtalex/hipster-frontend:v0.0.2
```

- Обновим в манифесте версию образа
- Применим новый манифест, параллельно запустим отслеживание происходящего:

```console
kubectl apply -f frontend-replicaset.yaml | kubectl get pods -l app=frontend -w

NAME             READY   STATUS    RESTARTS   AGE
frontend-2g8vl   1/1     Running   0          3m19s
frontend-7nzld   1/1     Running   0          6m11s
frontend-hgsx4   1/1     Running   0          3m19s
```

Давайте проверим образ, указанный в ReplicaSet:

```console
kubectl get replicaset frontend -o=jsonpath='{.spec.template.spec.containers[0].image}'

kovtalex/hipster-frontend:v0.0.2%  
```

И образ из которого сейчас запущены pod, управляемые контроллером:

```console
kubectl get pods -l app=frontend -o=jsonpath='{.items[0:3].spec.containers[0].image}'

kovtalex/hipster-frontend:v0.0.1 kovtalex/hipster-frontend:v0.0.1 kovtalex/hipster-frontend:v0.0.1%  
```

> Обратим внимание на использование ключа **-o jsonpath** для форматирования вывода. Подробнее с данным функционалом kubectl можно ознакомиться по [ссылке](https://kubernetes.io/docs/reference/kubectl/jsonpath/).

- Удалим все запущенные pod и после их пересоздания еще раз проверим, из какого образа они развернулись

```console
kubectl get pods -l app=frontend -o=jsonpath='{.items[0:3].spec.containers[0].image}'

kovtalex/hipster-frontend:v0.0.2 kovtalex/hipster-frontend:v0.0.2 kovtalex/hipster-frontend:v0.0.2%
```

> Обновление ReplicaSet не повлекло обновление запущенных pod по причине того, что ReplicaSet не умеет рестартовать запущенные поды при обновлении шаблона

### Deployment

Для начала - воспроизведем действия, проделанные с микросервисом **frontend** для микросервиса **paymentService**.

Результат:

- Собранный и помещенный в Docker Hub образ с двумя тегами **v0.0.1** и **v0.0.2**
- Валидный манифест **paymentservice-replicaset.yaml** с тремя репликами, разворачивающими из образа версии v0.0.1

```console
docker build -t kovtalex/hipster-paymentservice:v0.0.1 .
docker build -t kovtalex/hipster-paymentservice:v0.0.2 .
docker push kovtalex/hipster-paymentservice:v0.0.1
docker push kovtalex/hipster-paymentservice:v0.0.2
```

Приступим к написанию Deployment манифеста для сервиса **payment**

- Скопируем содержимое файла **paymentservicereplicaset.yaml** в файл **paymentservice-deployment.yaml**
- Изменим поле **kind** с **ReplicaSet** на **Deployment**
- Манифест готов 😉 Применим его и убедимся, что в кластере Kubernetes действительно запустилось три реплики сервиса **payment** и каждая из них находится в состоянии **Ready**
- Обратим внимание, что помимо Deployment (kubectl get deployments) и трех pod, у нас появился новый ReplicaSet (kubectl get rs)

```yml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: frontend
  labels:
    app: frontend
spec:
  replicas: 3
  selector:
    matchLabels:
      app: frontend
  template:
    metadata:
      labels:
        app: frontend
    spec:
      containers:
      - name: server
        image: kovtalex/hipster-frontend:v0.0.1
        env:
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

```console
kubectl apply -f paymentservice-replicaset.yaml

kubectl get rs paymentservice
NAME             DESIRED   CURRENT   READY   AGE
paymentservice   3         3         3       22s
```

```console
kubectl apply -f paymentservice-deployment.yaml

kubectl get rs -l app=paymentservice

NAME                       DESIRED   CURRENT   READY   AGE
paymentservice-84f44df66   3         3         3       60s
```

```console
kubectl get deployments

NAME             READY   UP-TO-DATE   AVAILABLE   AGE
paymentservice   3/3     3            3           112s
```

### Обновление Deployment

Давайте попробуем обновить наш Deployment на версию образа **v0.0.2**

Обратим внимание на последовательность обновления pod. По умолчанию применяется стратегия **Rolling Update**:

- Создание одного нового pod с версией образа **v0.0.2**
- Удаление одного из старых pod
- Создание еще одного нового pod
- ...

```console
kubectl apply -f paymentservice-deployment.yaml | kubectl get pods -l app=paymentservice -w

NAME                             READY   STATUS    RESTARTS   AGE
paymentservice-84f44df66-h2hxp   1/1     Running   0          3m14s
paymentservice-84f44df66-jwrsj   1/1     Running   0          3m14s
paymentservice-84f44df66-kzrkr   1/1     Running   0          3m14s
paymentservice-7845cdfff9-tmxgp   0/1     Pending   0          0s
paymentservice-7845cdfff9-tmxgp   0/1     Pending   0          0s
paymentservice-7845cdfff9-tmxgp   0/1     ContainerCreating   0          0s
paymentservice-7845cdfff9-tmxgp   1/1     Running             0          3s
paymentservice-84f44df66-h2hxp    1/1     Terminating         0          3m18s
paymentservice-7845cdfff9-5c7q8   0/1     Pending             0          0s
paymentservice-7845cdfff9-5c7q8   0/1     Pending             0          1s
paymentservice-7845cdfff9-5c7q8   0/1     ContainerCreating   0          1s
paymentservice-7845cdfff9-5c7q8   1/1     Running             0          4s
paymentservice-84f44df66-jwrsj    1/1     Terminating         0          3m22s
paymentservice-7845cdfff9-bs59h   0/1     Pending             0          0s
paymentservice-7845cdfff9-bs59h   0/1     Pending             0          0s
paymentservice-7845cdfff9-bs59h   0/1     ContainerCreating   0          1s
paymentservice-7845cdfff9-bs59h   1/1     Running             0          5s
paymentservice-84f44df66-kzrkr    1/1     Terminating         0          3m28s
```

Убедимся что:

- Все новые pod развернуты из образа **v0.0.2**
- Создано два ReplicaSet:
  - Один (новый) управляет тремя репликами pod с образом **v0.0.2**
  - Второй (старый) управляет нулем реплик pod с образом **v0.0.1**

Также мы можем посмотреть на историю версий нашего Deployment:

```console
kubectl get pods -l app=paymentservice -o=jsonpath='{.items[0:3].spec.containers[0].image}'

kovtalex/hipster-paymentservice:v0.0.2 kovtalex/hipster-paymentservice:v0.0.2 kovtalex/hipster-paymentservice:v0.0.2%
```

```console
kubectl get rs

NAME                        DESIRED   CURRENT   READY   AGE
frontend                    3         3         3       36m
paymentservice-7845cdfff9   3         3         3       4m47s
paymentservice-84f44df66    0         0         0       8m2s
```

```console
kubectl rollout history deployment paymentservice
deployment.apps/paymentservice
REVISION  CHANGE-CAUSE
1         <none>
2         <none>
```

### Deployment | Rollback

Представим, что обновление по каким-то причинам произошло неудачно и нам необходимо сделать откат. Kubernetes предоставляет такую возможность:

```console
kubectl rollout undo deployment paymentservice --to-revision=1 | kubectl get rs -l app=paymentservice -w

NAME                        DESIRED   CURRENT   READY   AGE
paymentservice-7845cdfff9   3         3         3       7m12s
paymentservice-84f44df66    0         0         0       10m
paymentservice-84f44df66    0         0         0       10m
paymentservice-84f44df66    1         0         0       10m
paymentservice-84f44df66    1         0         0       10m
paymentservice-84f44df66    1         1         0       10m
paymentservice-84f44df66    1         1         1       10m
paymentservice-7845cdfff9   2         3         3       7m15s
paymentservice-84f44df66    2         1         1       10m
paymentservice-7845cdfff9   2         3         3       7m15s
paymentservice-84f44df66    2         1         1       10m
paymentservice-7845cdfff9   2         2         2       7m15s
paymentservice-84f44df66    2         2         1       10m
paymentservice-84f44df66    2         2         2       10m
paymentservice-7845cdfff9   1         2         2       7m17s
paymentservice-84f44df66    3         2         2       10m
paymentservice-7845cdfff9   1         2         2       7m17s
paymentservice-7845cdfff9   1         1         1       7m17s
paymentservice-84f44df66    3         2         2       10m
paymentservice-84f44df66    3         3         2       10m
paymentservice-84f44df66    3         3         3       10m
paymentservice-7845cdfff9   0         1         1       7m19s
paymentservice-7845cdfff9   0         1         1       7m20s
paymentservice-7845cdfff9   0         0         0       7m20s
```

В выводе мы можем наблюдать, как происходит постепенное масштабирование вниз "нового" ReplicaSet, и масштабирование вверх "старого".

### Deployment | Задание со ⭐

С использованием параметров **maxSurge** и **maxUnavailable** самостоятельно реализуем два следующих сценария развертывания:

- Аналог blue-green:
  1. Развертывание трех новых pod
  2. Удаление трех старых pod
- Reverse Rolling Update:
  1. Удаление одного старого pod
  2. Создание одного нового pod

[Документация](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/#strategy) с описанием стратегий развертывания для Deployment.

maxSurge - определяет количество реплик, которое можно создать с превышением значения replicas  
Можно задавать как абсолютное число, так и процент. Default: 25%

maxUnavailable - определяет количество реплик от общего числа, которое можно "уронить"  
Аналогично, задается в процентах или числом. Default: 25%

В результате должно получиться два манифеста:

- paymentservice-deployment-bg.yaml

Для реализации аналога blue-green развертывания устанавливаем значения:

- maxSurge равным **3** для превышения количества требуемых pods
- maxUnavailable равным **0** для ограничения минимального количества недоступных pods

```yml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: paymentservice
  labels:
    app: paymentservice
spec:
  replicas: 3
  strategy:
    type: RollingUpdate
    rollingUpdate:
      # Количество реплик, которое можно создать с превышением значения replicas
      # Можно задавать как абсолютное число, так и процент. Default: 25%
      maxSurge: 3
      # Количество реплик от общего числа, которое можно "уронить"
      # Аналогично, задается в процентах или числом. Default: 25%
      maxUnavailable: 0
  selector:
    matchLabels:
      app: paymentservice
  template:
    metadata:
      labels:
        app: paymentservice
    spec:
      containers:
      - name: server
        image: kovtalex/hipster-paymentservice:v0.0.1
```

Применим манифест:

```console
kubectl apply -f paymentservice-deployment-bg.yaml
deployment.apps/paymentservice created

kubectl get pods
NAME                             READY   STATUS    RESTARTS   AGE
paymentservice-84f44df66-kr62g   1/1     Running   0          30s
paymentservice-84f44df66-ltsx8   1/1     Running   0          30s
paymentservice-84f44df66-nn8ml   1/1     Running   0          30s
```

В манифесте **paymentservice-deployment-bg.yaml** меняем версию образа на **v0.0.2** и применяем:

```console
kubectl apply -f paymentservice-deployment-bg.yaml
deployment.apps/paymentservice configured

kubectl get pods -w
NAME                             READY   STATUS    RESTARTS   AGE
paymentservice-84f44df66-kr62g   1/1     Running   0          109s
paymentservice-84f44df66-ltsx8   1/1     Running   0          109s
paymentservice-84f44df66-nn8ml   1/1     Running   0          109s
paymentservice-7845cdfff9-bgr7k   0/1     Pending   0          0s
paymentservice-7845cdfff9-n6nqw   0/1     Pending   0          0s
paymentservice-7845cdfff9-snjpm   0/1     Pending   0          0s
paymentservice-7845cdfff9-snjpm   0/1     Pending   0          0s
paymentservice-7845cdfff9-bgr7k   0/1     Pending   0          0s
paymentservice-7845cdfff9-n6nqw   0/1     Pending   0          0s
paymentservice-7845cdfff9-n6nqw   0/1     ContainerCreating   0          0s
paymentservice-7845cdfff9-bgr7k   0/1     ContainerCreating   0          0s
paymentservice-7845cdfff9-snjpm   0/1     ContainerCreating   0          0s
paymentservice-7845cdfff9-snjpm   1/1     Running             0          2s
paymentservice-7845cdfff9-n6nqw   1/1     Running             0          2s
paymentservice-7845cdfff9-bgr7k   1/1     Running             0          3s
paymentservice-84f44df66-nn8ml    1/1     Terminating         0          2m1s
paymentservice-84f44df66-ltsx8    1/1     Terminating         0          2m2s
paymentservice-84f44df66-kr62g    1/1     Terminating         0          2m2
```

> Как видно выше, сначала создаются три новых пода, а затем удаляются три старых.

- paymentservice-deployment-reverse.yaml

Для реализации Reverse Rolling Update устанавливаем значения:

- maxSurge равным **1** для превышения количества требуемых pods
- maxUnavailable равным **1** для ограничения минимального количества недоступных pods

```yml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: paymentservice
  labels:
    app: paymentservice
spec:
  replicas: 3
  strategy:
    type: RollingUpdate
    rollingUpdate:
      # Количество реплик, которое можно создать с превышением значения replicas
      # Можно задавать как абсолютное число, так и процент. Default: 25%
      maxSurge: 1
      # Количество реплик от общего числа, которое можно "уронить"
      # Аналогично, задается в процентах или числом. Default: 25%
      maxUnavailable: 1
  selector:
    matchLabels:
      app: paymentservice
  template:
    metadata:
      labels:
        app: paymentservice
    spec:
      containers:
      - name: server
        image: kovtalex/hipster-paymentservice:v0.0.1
```

Проверяем результат:

```console
kubectl apply -f paymentservice-deployment-reverse.yaml | kubectl get pods -w

NAME                              READY   STATUS    RESTARTS   AGE
paymentservice-7845cdfff9-2hgrh   1/1     Running   0          92s
paymentservice-7845cdfff9-ffg84   1/1     Running   0          91s
paymentservice-7845cdfff9-vqjm2   1/1     Running   0          91s
paymentservice-84f44df66-t7rph    0/1     Pending   0          0s
paymentservice-7845cdfff9-ffg84   1/1     Terminating   0          91s
paymentservice-84f44df66-t7rph    0/1     Pending       0          1s
paymentservice-84f44df66-jhw47    0/1     Pending       0          0s
paymentservice-84f44df66-t7rph    0/1     ContainerCreating   0          1s
paymentservice-84f44df66-jhw47    0/1     Pending             0          0s
paymentservice-84f44df66-jhw47    0/1     ContainerCreating   0          0s
paymentservice-84f44df66-t7rph    1/1     Running             0          2s
paymentservice-7845cdfff9-2hgrh   1/1     Terminating         0          94s
paymentservice-84f44df66-jhw47    1/1     Running             0          1s
paymentservice-84f44df66-sjllv    0/1     Pending             0          0s
paymentservice-84f44df66-sjllv    0/1     Pending             0          1s
paymentservice-84f44df66-sjllv    0/1     ContainerCreating   0          1s
paymentservice-7845cdfff9-vqjm2   1/1     Terminating         0          94s
paymentservice-84f44df66-sjllv    1/1     Running             0          3s
paymentservice-7845cdfff9-ffg84   0/1     Terminating         0          2m3s
paymentservice-7845cdfff9-2hgrh   0/1     Terminating         0          2m5s
paymentservice-7845cdfff9-vqjm2   0/1     Terminating         0          2m5s
paymentservice-7845cdfff9-vqjm2   0/1     Terminating         0          2m6s
paymentservice-7845cdfff9-vqjm2   0/1     Terminating         0          2m6s
paymentservice-7845cdfff9-2hgrh   0/1     Terminating         0          2m12s
paymentservice-7845cdfff9-2hgrh   0/1     Terminating         0          2m12s
paymentservice-7845cdfff9-ffg84   0/1     Terminating         0          2m11s
paymentservice-7845cdfff9-ffg84   0/1     Terminating         0          2m12s
```

### Probes

Мы научились разворачивать и обновлять наши микросервисы, но можем ли быть уверены, что они корректно работают после выкатки? Один из механизмов Kubernetes, позволяющий нам проверить это - [Probes](https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/).

Давайте на примере микросервиса **frontend** посмотрим на то, как probes влияют на процесс развертывания.

- Создадим манифест **frontend-deployment.yaml** из которого можно развернуть три реплики pod с тегом образа **v0.0.1**
- Добавим туда описание *readinessProbe*. Описание можно взять из манифеста по [ссылке](https://github.com/GoogleCloudPlatform/microservices-demo/blob/master/kubernetes-manifests/frontend.yaml).

Применим манифест с **readinessProbe**. Если все сделано правильно, то мы вновь увидим три запущенных pod в описании которых (**kubectl describe pod**) будет указание на наличие **readinessProbe** и ее параметры.

Давайте попробуем сымитировать некорректную работу приложения и посмотрим, как будет вести себя обновление:

- Заменим в описании пробы URL **/_healthz** на **/_health**
- Развернем версию **v0.0.2**

```console
kubectl apply -f frontend-deployment.yaml
```

Если посмотреть на текущее состояние нашего микросервиса, мы увидим, что был создан один pod новой версии, но его статус готовности **0/1**:

Команда kubectl describe pod поможет нам понять причину:

```console
kubectl describe pod frontend-78c57b6df6-vvvbt

Events:
  Type     Reason     Age               From                   Message
  ----     ------     ----              ----                   -------
  Warning  Unhealthy  4s (x2 over 14s)  kubelet, kind-worker3  Readiness probe failed: HTTP probe failed with statuscode: 404
```

Как можно было заметить, пока **readinessProbe** для нового pod не станет успешной - Deployment не будет пытаться продолжить обновление.

На данном этапе может возникнуть вопрос - как автоматически отследить успешность выполнения Deployment (например для запуска в CI/CD).

В этом нам может помочь следующая команда:

```console
kubectl rollout status deployment/frontend
```

Таким образом описание pipeline, включающее в себя шаг развертывания и шаг отката, в самом простом случае может выглядеть так (синтаксис GitLab CI):

```yml
deploy_job:
  stage: deploy
  script:
    - kubectl apply -f frontend-deployment.yaml
    - kubectl rollout status deployment/frontend --timeout=60s

rollback_deploy_job:
  stage: rollback
  script:
    - kubectl rollout undo deployment/frontend
  when: on_failure
```

### DaemonSet

Рассмотрим еще один контроллер Kubernetes. Отличительная особенность DaemonSet в том, что при его применении на каждом физическом хосте создается по одному экземпляру pod, описанного в спецификации.

Типичные кейсы использования DaemonSet:

- Сетевые плагины
- Утилиты для сбора и отправки логов (Fluent Bit, Fluentd, etc...)
- Различные утилиты для мониторинга (Node Exporter, etc...)
- ...

### DaemonSet | Задание со ⭐

Опробуем DaemonSet на примере [Node Exporter](https://github.com/prometheus/node_exporter)

- Найдем в интернете [манифест](https://github.com/coreos/kube-prometheus/tree/master/manifests) **node-exporter-daemonset.yaml** для развертывания DaemonSet с Node Exporter
- После применения данного DaemonSet и выполнения команды: kubectl port-forward <имя любого pod в DaemonSet> 9100:9100 доступны на localhost: curl localhost:9100/metrics

Подготовим манифесты и развернем Node Exporter как DaemonSet:

```console
kubectl create ns monitoring
namespace/monitoring created

kubectl apply -f node-exporter-serviceAccount.yaml
serviceaccount/node-exporter created

kubectl apply -f node-exporter-clusterRole.yaml
clusterrole.rbac.authorization.k8s.io/node-exporter created

kubectl apply -f node-exporter-clusterRoleBinding.yaml
clusterrolebinding.rbac.authorization.k8s.io/node-exporter created

kubectl apply -f node-exporter-daemonset.yaml
daemonset.apps/node-exporter created

kubectl apply -f node-exporter-service.yaml
service/node-exporter created
```

Проверим созданные pods:

```console
kubectl get pods -n monitoring

NAME                  READY   STATUS    RESTARTS   AGE
node-exporter-j657t   2/2     Running   0          110s
node-exporter-k6nwd   2/2     Running   0          105s
node-exporter-vsrzp   2/2     Running   0          119s
```

В соседнем терминале запустим проброс порта:

```console
kubectl port-forward node-exporter-j657t 9100:9100 -n monitoring

Forwarding from 127.0.0.1:9100 -> 9100
Forwarding from [::1]:9100 -> 9100
```

И убедимся, что мы можем получать метрики:

```console
curl localhost:9100/metrics

# TYPE go_gc_duration_seconds summary
go_gc_duration_seconds{quantile="0"} 0
go_gc_duration_seconds{quantile="0.25"} 0
go_gc_duration_seconds{quantile="0.5"} 0
go_gc_duration_seconds{quantile="0.75"} 0
go_gc_duration_seconds{quantile="1"} 0
go_gc_duration_seconds_sum 0
go_gc_duration_seconds_count 0
# HELP go_goroutines Number of goroutines that currently exist.
# TYPE go_goroutines gauge
go_goroutines 6
# HELP go_info Information about the Go environment.
# TYPE go_info gauge
go_info{version="go1.12.5"} 1
# HELP go_memstats_alloc_bytes Number of bytes allocated and still in use.
# TYPE go_memstats_alloc_bytes gauge
go_memstats_alloc_bytes 2.300448e+06
# HELP go_memstats_alloc_bytes_total Total number of bytes allocated, even if freed.
# TYPE go_memstats_alloc_bytes_total counter
go_memstats_alloc_bytes_total 2.300448e+06
# HELP go_memstats_buck_hash_sys_bytes Number of bytes used by the profiling bucket hash table.
# TYPE go_memstats_buck_hash_sys_bytes gauge
go_memstats_buck_hash_sys_bytes 1.444017e+06
# HELP go_memstats_frees_total Total number of frees.
...
```

### DaemonSet | Задание с ⭐⭐

- Как правило, мониторинг требуется не только для worker, но и для master нод. При этом, по умолчанию, pod управляемые DaemonSet на master нодах не разворачиваются
- Найдем способ модернизировать свой DaemonSet таким образом, чтобы Node Exporter был развернут как на master, так и на worker нодах (конфигурацию самих нод изменять нельзя)
- Отразим изменения в манифесте

Материал по теме: [Taint and Toleration](https://kubernetes.io/docs/concepts/scheduling-eviction/taint-and-toleration/).

Решение: для развертывания DaemonSet на master нодах нам необходимо выдать **допуск** поду.  
Правим наш **node-exporter-daemonset.yaml**:

```yml
tolerations:
- operator: Exists
```

Применяем манифест и проверяем, что DaemonSet развернулся на master нодах.

```console
kubectl apply -f node-exporter-daemonset.yaml
daemonset.apps/node-exporter configured

kubectl get pods -n monitoring -o wide
NAME                  READY   STATUS    RESTARTS   AGE   IP           NODE                  NOMINATED NODE   READINESS GATES
node-exporter-25d4s   2/2     Running   0          45m   172.18.0.6   kind-worker3          <none>           <none>
node-exporter-8dp28   2/2     Running   0          45m   172.18.0.4   kind-control-plane    <none>           <none>
node-exporter-bb76j   2/2     Running   0          45m   172.18.0.7   kind-control-plane2   <none>           <none>
node-exporter-dzmm9   2/2     Running   0          45m   172.18.0.5   kind-control-plane3   <none>           <none>
node-exporter-p9sn4   2/2     Running   0          45m   172.18.0.3   kind-worker2          <none>           <none>
node-exporter-s8dh7   2/2     Running   0          45m   172.18.0.8   kind-worker           <none>           <none>
````

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

- В корне репозитория создадим директорию kubernetesintro/web и поместим туда готовый Dockerfile
- Соберем из Dockerfile образ контейнера и поместим его в публичный Container Registry (например, Docker Hub)

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

- scheduler определил, на какой ноде запускать pod
- kubelet скачал необходимый образ и запустил контейнер

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

- **image** init контейнера должен содержать **wget** (например, можно использовать busybox:1.31.0 или любой другой busybox актуальной версии)
- command init контейнера (аналог ENTRYPOINT в Dockerfile) укажите следующую:

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

- Склонируем [репозиторий](https://github.com/GoogleCloudPlatform/microservices-demo) и соберем собственный образ для **frontend** (используем готовый Dockerfile)
- Поместим собранный образ на Docker Hub

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

- **kubectl run** - запустить ресурс
- **frontend** - с именем frontend
- **--image** - из образа kovtalex/hipster-frontend:v0.0.1 (подставьте свой образ)
- **--restart=Never** указываем на то, что в качестве ресурса запускаем pod. [Подробности](https://kubernetes.io/docs/reference/kubectl/conventions/)

Один из распространенных кейсов использования ad-hoc режима - генерация манифестов средствами kubectl:

```console
kubectl run frontend --image kovtalex/hipster-frontend:v0.0.1 --restart=Never --dryrun -o yaml > frontend-pod.yaml
```

Рассмотрим дополнительные ключи:

- **--dry-run** - вывод информации о ресурсе без его реального создания
- **-o yaml** - форматирование вывода в YAML
- **> frontend-pod.yaml** - перенаправление вывода в файл

### Hipster Shop | Задание со ⭐

- Выясним причину, по которой pod **frontend** находится в статусе **Error**
- Создадим новый манифест **frontend-pod-healthy.yaml**. При его применении ошибка должна исчезнуть. Подсказки можно найти:
  - В логах - **kubectl logs frontend**
  - В манифесте по [ссылке](https://github.com/GoogleCloudPlatform/microservices-demo/blob/master/kubernetes-manifests/frontend.yaml)
- В результате, после применения исправленного манифеста pod **frontend** должен находиться в статусе **Running**
- Поместим исправленный манифест **frontend-pod-healthy.yaml** в директорию **kubernetes-intro**

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
