# kovtalex_platform

## Security

### task01

- Создать Service Account **bob**, дать ему роль **admin** в рамках всего кластера
- Создать Service Account **dave** без доступа к кластеру

### task02

- Создать Namespace prometheus
- Создать Service Account **carol** в этом Namespace
- Дать всем Service Account в Namespace prometheus возможность делать **get, list, watch** в отношении Pods всего кластера

### task03

- Создать Namespace **dev**
- Создать Service Account **jane** в Namespace **dev**
- Дать **jane** роль **admin** в рамках Namespace **dev**
- Создать Service Account **ken** в Namespace **dev**
- Дать **ken** роль **view** в рамках Namespace **dev**

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
- Применим новый манифест, параллельно запустите отслеживание происходящего:

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
