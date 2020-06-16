# kovtalex_platform

## Hashicorp Vault + K8s

### План

В ходе работы мы:

- установим кластер vault в kubernetes
- научимся создавать секреты и политики
- настроим авторизацию в vault через kubernetes sa
- сделаем под с контейнером nginx, в который прокинем секреты из vault через consul-template

Вспомогательные ссылки:

- [vault](https://learn.hashicorp.com/vault/identity-access-management/vault-agent-k8s#step-1-create-a-service-account)
- [vault-guides](https://github.com/hashicorp/vault-guides.git)

### Инсталляция hashicorp vault HA в k8s

Добавим репозиторий:

```console
helm repo add hashicorp https://helm.releases.hashicorp.com
helm repo update
```

Установим consul:

```console
helm upgrade --install consul hashicorp/consul
Release "consul" does not exist. Installing it now.
NAME: consul
LAST DEPLOYED: Fri Jun 12 18:38:23 2020
NAMESPACE: default
STATUS: deployed
REVISION: 1
NOTES:
Thank you for installing HashiCorp Consul!

Now that you have deployed Consul, you should look over the docs on using
Consul with Kubernetes available here:

https://www.consul.io/docs/platform/k8s/index.html


Your release is named consul.

To learn more about the release if you are using Helm 2, run:

  $ helm status consul
  $ helm get consul

To learn more about the release if you are using Helm 3, run:

  $ helm status consul
  $ helm get all consul
```

### Отредактируем параметры установки в values.yaml

vault.values.yaml:

```yml
server:  
  standalone:
    enabled: false

  ha:
    enabled: true

ui:
  enabled: true
```

### Установим vault

```console
helm upgrade --install vault hashicorp/vault -f vault.values.yaml
Release "vault" does not exist. Installing it now.
NAME: vault
LAST DEPLOYED: Fri Jun 12 18:39:19 2020
NAMESPACE: default
STATUS: deployed
REVISION: 1
TEST SUITE: None
NOTES:
Thank you for installing HashiCorp Vault!

Now that you have deployed Vault, you should look over the docs on using
Vault with Kubernetes available here:

https://www.vaultproject.io/docs/


Your release is named vault. To learn more about the release, try:

  $ helm status vault
  $ helm get vault
```

```console
kubectl get pods

NAME                                    READY   STATUS    RESTARTS   AGE
consul-consul-29tw4                     1/1     Running   0          76s
consul-consul-78t4d                     1/1     Running   0          76s
consul-consul-854t7                     1/1     Running   0          76s
consul-consul-server-0                  1/1     Running   0          76s
consul-consul-server-1                  1/1     Running   0          76s
consul-consul-server-2                  1/1     Running   0          76s
vault-0                                 0/1     Running   0          15s
vault-1                                 0/1     Running   0          15s
vault-2                                 0/1     Running   0          15s
vault-agent-injector-7898f4df86-64lcr   1/1     Running   0          15s
```

### Инициализируем vault

- Проведем инициализацию черерз любой под vault'а kubectl

```console
kubectl exec -it vault-0 -- vault operator init --key-shares=1 --key-threshold=1
Unseal Key 1: FVvyfk+VawPVOSm+gEAp9YlB17xTctbooy7/v3xmLnQ=

Initial Root Token: s.y71KGil4zgA42MK1VmQEuTs7
```

- Сохраним ключи, полученные при инициализации
  - Unseal Key 1: FVvyfk+VawPVOSm+gEAp9YlB17xTctbooy7/v3xmLnQ=
  - Initial Root Token: s.y71KGil4zgA42MK1VmQEuTs7

### Проверим состояние vault'а

```console
kubectl exec -it vault-0 -- vault status
Key                Value
---                -----
Seal Type          shamir
Initialized        true
Sealed             true
Total Shares       1
Threshold          1
Unseal Progress    0/1
Unseal Nonce       n/a
Version            1.4.2
HA Enabled         true
```

### Распечатаем vault

- Обратите внимание на переменные окружения в подах

```console
kubectl exec -it vault-0 env | grep VAULT_ADDR
VAULT_ADDR=http://127.0.0.1:8200
```

- Распечатать нужно каждый под

```console
kubectl exec -it vault-0 -- vault operator unseal 'FVvyfk+VawPVOSm+gEAp9YlB17xTctbooy7/v3xmLnQ='
Key                    Value
---                    -----
Seal Type              shamir
Initialized            true
Sealed                 false
Total Shares           1
Threshold              1
Version                1.4.2
Cluster Name           vault-cluster-5dddd753
Cluster ID             e6a34344-6fd5-0ff9-8d37-b4f702bdc5ea
HA Enabled             true
HA Cluster             https://vault-1.vault-internal:8201
HA Mode                standby
Active Node Address    http://10.60.2.6:8200
```

```console
kubectl exec -it vault-1 -- vault operator unseal 'FVvyfk+VawPVOSm+gEAp9YlB17xTctbooy7/v3xmLnQ='
Key                    Value
---                    -----
Seal Type              shamir
Initialized            true
Sealed                 false
Total Shares           1
Threshold              1
Version                1.4.2
Cluster Name           vault-cluster-5dddd753
Cluster ID             e6a34344-6fd5-0ff9-8d37-b4f702bdc5ea
HA Enabled             true
HA Cluster             n/a
HA Mode                standby
Active Node Address    <none>
```

```console
kubectl exec -it vault-2 -- vault operator unseal 'FVvyfk+VawPVOSm+gEAp9YlB17xTctbooy7/v3xmLnQ='
Key                    Value
---                    -----
Seal Type              shamir
Initialized            true
Sealed                 false
Total Shares           1
Threshold              1
Version                1.4.2
Cluster Name           vault-cluster-5dddd753
Cluster ID             e6a34344-6fd5-0ff9-8d37-b4f702bdc5ea
HA Enabled             true
HA Cluster             https://vault-1.vault-internal:8201
HA Mode                standby
Active Node Address    http://10.60.2.6:8200
```

### Посмотрим список доступных авторизаций

Получим ошибку:

```console
kubectl exec -it vault-0 -- vault auth list
Error listing enabled authentications: Error making API request.

URL: GET http://127.0.0.1:8200/v1/sys/auth
Code: 400. Errors:

* missing client token
```

### Залогинимся в vault (у нас есть root token)

```console
kubectl exec -it vault-0 -- vault login
Token (will be hidden):
Success! You are now authenticated. The token information displayed below
is already stored in the token helper. You do NOT need to run "vault login"
again. Future Vault requests will automatically use this token.

Key                  Value
---                  -----
token                s.y71KGil4zgA42MK1VmQEuTs7
token_accessor       zs5lY2o23wAMYBjQju47I90R
token_duration       ∞
token_renewable      false
token_policies       ["root"]
identity_policies    []
policies             ["root"]
```

- Повторно запросим список авторизаций

```console
kubectl exec -it vault-0 -- vault auth list
Path      Type     Accessor               Description
----      ----     --------               -----------
token/    token    auth_token_c82675cb    token based credentials
```

### Заведем секреты

```console
kubectl exec -it vault-0 -- vault secrets enable --path=otus kv
Success! Enabled the kv secrets engine at: otus/
```

```console
kubectl exec -it vault-0 -- vault secrets list --detailed
Path          Plugin       Accessor              Default TTL    Max TTL    Force No Cache    Replication    Seal Wrap    External Entropy Access    Options    Description                                                UUID
----          ------       --------              -----------    -------    --------------    -----------    ---------    -----------------------    -------    -----------                                                ----
cubbyhole/    cubbyhole    cubbyhole_571dafbb    n/a            n/a        false             local          false        false                      map[]      per-token private secret storage                           e1acbd2f-6c75-d39f-e5e0-987f1eb4eb61
identity/     identity     identity_1545b700     system         system     false             replicated     false        false                      map[]      identity store                                             918fdcbf-e74a-3f5e-d37b-20febd024dbc
otus/         kv           kv_5a4a34ef           system         system     false             replicated     false        false                      map[]      n/a                                                        3183b6fe-e4a9-8ed5-37d9-5773e336b730
sys/          system       system_d89d7a08       n/a            n/a        false             replicated     false        false                      map[]      system endpoints used for control, policy and debugging    b63b40cf-c24a-0dff-6c26-5c9ce69d5463
```

```console
kubectl exec -it vault-0 -- vault kv put otus/otus-ro/config username='otus' password='asajkjkahs'
Success! Data written to: otus/otus-ro/config


kubectl exec -it vault-0 -- vault kv put otus/otus-rw/config username='otus' password='asajkjkahs'
Success! Data written to: otus/otus-rw/config
```

```console
kubectl exec -it vault-0 -- vault read otus/otus-ro/config
Key                 Value
---                 -----
refresh_interval    768h
password            asajkjkahs
username            otus
```

```console
kubectl exec -it vault-0 -- vault kv get otus/otus-rw/config
====== Data ======
Key         Value
---         -----
password    asajkjkahs
username    otus
```

### Включим авторизацию черерз k8s

```console
kubectl exec -it vault-0 -- vault auth enable kubernetes
Success! Enabled kubernetes auth method at: kubernetes/
```

```console
kubectl exec -it vault-0 -- vault auth list
Path           Type          Accessor                    Description
----           ----          --------                    -----------
kubernetes/    kubernetes    auth_kubernetes_2bbb6f48    n/a
token/         token         auth_token_c82675cb         token based credentials
```

### Создадим yaml для ClusterRoleBinding

vault-auth-service-account.yml

```yml
apiVersion: rbac.authorization.k8s.io/v1beta1
kind: ClusterRoleBinding
metadata:
  name: role-tokenreview-binding
  namespace: default
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: system:auth-delegator
subjects:
- kind: ServiceAccount
  name: vault-auth
  namespace: default
```

### Создадим Service Account vault-auth и применим ClusterRoleBinding

```console
kubectl create serviceaccount vault-auth
serviceaccount/vault-auth created


kubectl apply -f vault-auth-service-account.yml
clusterrolebinding.rbac.authorization.k8s.io/role-tokenreview-binding created
```

### Подготовим переменные для записи в конфиг кубер авторизации

```console
export VAULT_SA_NAME=$(kubectl get sa vault-auth -o jsonpath="{.secrets[*]['name']}")
export SA_JWT_TOKEN=$(kubectl get secret $VAULT_SA_NAME -o jsonpath="{.data.token}" | base64 --decode; echo)
export SA_CA_CRT=$(kubectl get secret $VAULT_SA_NAME -o jsonpath="{.data['ca\.crt']}" | base64 --decode; echo)
export K8S_HOST=$(more ~/.kube/config | grep server |awk '/http/ {print $NF}')

### alternative way
export K8S_HOST=$(kubectl cluster-info | grep 'Kubernetes master' | awk '/https/ {print $NF}' | sed 's/\x1b\[[0-9;]*m//g' )
````

### Запишем конфиг в vault

```console
kubectl exec -it vault-0 -- vault write auth/kubernetes/config \
token_reviewer_jwt="$SA_JWT_TOKEN" \
kubernetes_host="$K8S_HOST" \
kubernetes_ca_cert="$SA_CA_CRT"

Success! Data written to: auth/kubernetes/config
```

### Создадим файл политики

```json
tee otus-policy.hcl <<EOF
path "otus/otus-ro/*" {
  capabilities = ["read", "list"]
}
path "otus/otus-rw/*" {
  capabilities = ["read", "create", "list"]
}
EOF
```

### Создадим политку и роль в vault

```console
kubectl cp otus-policy.hcl vault-0:/home/vault
kubectl exec -it vault-0 -- vault policy write otus-policy /home/vault/otus-policy.hcl
Success! Uploaded policy: otus-policy
```

```console
kubectl exec -it vault-0 -- vault write auth/kubernetes/role/otus \
bound_service_account_names=vault-auth \
bound_service_account_namespaces=default policies=otus-policy ttl=24h
Success! Data written to: auth/kubernetes/role/otus
```

### Проверим как работает авторизация

- Создадим под с привязанным сервис аккоунтом и установим туда curl и jq

```console
kubectl run --generator=run-pod/v1 tmp --rm -i --tty --serviceaccount=vault-auth --image alpine:3.7
apk add curl jq
```

- Залогинимся и получим клиентский токен

```console
VAULT_ADDR=http://vault:8200
KUBE_TOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)

curl --request POST --data '{"jwt": "'$KUBE_TOKEN'", "role": "otus"}' $VAULT_ADDR/v1/auth/kubernetes/login | jq
{
  "request_id": "2af65405-1324-9b34-cd1a-77f2d8e9badb",
  "lease_id": "",
  "renewable": false,
  "lease_duration": 0,
  "data": null,
  "wrap_info": null,
  "warnings": null,
  "auth": {
    "client_token": "s.q8YHiRZd6mkfByRn4BcpB6mm",
    "accessor": "pB3VsxHkPnISD82QQtbIImCz",
    "policies": [
      "default",
      "otus-policy"
    ],
    "token_policies": [
      "default",
      "otus-policy"
    ],
    "metadata": {
      "role": "otus",
      "service_account_name": "vault-auth",
      "service_account_namespace": "default",
      "service_account_secret_name": "vault-auth-token-rmwxz",
      "service_account_uid": "615c6a4f-8885-446c-ac78-c5026d718dca"
    },
    "lease_duration": 86400,
    "renewable": true,
    "entity_id": "188b9a87-f440-bcdf-0da7-165865147264",
    "token_type": "service",
    "orphan": true
  }
}

TOKEN=$(curl -k -s --request POST --data '{"jwt": "'$KUBE_TOKEN'", "role": "otus"}' $VAULT_ADDR/v1/auth/kubernetes/login | jq '.auth.client_token' | awk -F\" '{print $2}')
```

### Прочитаем Прочитаем записанные ранее секреты и попробуем их обновить

- Используем свой клиентский токен
- Проверим чтение

```console
curl --header "X-Vault-Token:s.SCbMdIL61rqmyqrCUldd1ocw" $VAULT_ADDR/v1/otus/otus-ro/config | jq
{
  "request_id": "3a29647c-8e75-4d56-7ed9-d641819c2dda",
  "lease_id": "",
  "renewable": false,
  "lease_duration": 2764800,
  "data": {
    "password": "asajkjkahs",
    "username": "otus"
  },
  "wrap_info": null,
  "warnings": null,
  "auth": null
}

curl --header "X-Vault-Token:s.SCbMdIL61rqmyqrCUldd1ocw" $VAULT_ADDR/v1/otus/otus-rw/config | jq
{
  "request_id": "48e1eab4-ebd5-b109-4fe7-ac080e7118c3",
  "lease_id": "",
  "renewable": false,
  "lease_duration": 2764800,
  "data": {
    "password": "asajkjkahs",
    "username": "otus"
  },
  "wrap_info": null,
  "warnings": null,
  "auth": null
}
```

- Проверим запись в otus-ro/config

```console
curl --request POST --data '{"bar": "baz"}' --header "X-Vault-Token:s.SCbMdIL61rqmyqrCUldd1ocw" $VAULT_ADDR/v1/otus/otus-ro/config | jq

{
  "errors": [
    "1 error occurred:\n\t* permission denied\n\n"
  ]
}
```

- Проверим запись в otus-ro/config1

```console
curl --request POST --data '{"bar": "baz"}' --header "X-Vault-Token:s.SCbMdIL61rqmyqrCUldd1ocw" $VAULT_ADDR/v1/otus/otus-rw/config1 | jq
```

```console
curl --header "X-Vault-Token:s.SCbMdIL61rqmyqrCUldd1ocw" $VAULT_ADDR/v1/otus/otus-rw/config1 | jq
{
  "request_id": "922fb606-f383-ecf6-6173-06ef2e9c3fcc",
  "lease_id": "",
  "renewable": false,
  "lease_duration": 2764800,
  "data": {
    "bar": "baz"
  },
  "wrap_info": null,
  "warnings": null,
  "auth": null
}
```

- Проверим запись в otus-ro/config1

```console
curl --request POST --data '{"bar": "baz"}' --header "X-Vault-Token:s.SCbMdIL61rqmyqrCUldd1ocw" $VAULT_ADDR/v1/otus/otus-rw/config | jq

{
  "errors": [
    "1 error occurred:\n\t* permission denied\n\n"
  ]
}
```

Доступ запрещен, так как у нас нет прав на обновление **otus/otus-ro/\***

Обновим otus-policy.hcl добавив **update**

```json
{
path "otus/otus-ro/*" {
  capabilities = ["read", "list"]
}
path "otus/otus-rw/*" {
  capabilities = ["read", "create", "update", "list"]
}
```

- Применим новые политики

```console
kubectl cp otus-policy.hcl vault-0:/home/vault
kubectl exec -it vault-0 -- vault policy write otus-policy /home/vault/otus-policy.hcl
Success! Uploaded policy: otus-policy
```

- И попробуем снова записать:

```console
curl --request POST --data '{"bar": "baz"}' --header "X-Vault-Token:s.SCbMdIL61rqmyqrCUldd1ocw" $VAULT_ADDR/v1/otus/otus-rw/config | jq

curl --header "X-Vault-Token:s.SCbMdIL61rqmyqrCUldd1ocw" $VAULT_ADDR/v1/otus/otus-rw/config | jq
{
  "request_id": "509645a1-bd6a-704e-c663-2d94ef465176",
  "lease_id": "",
  "renewable": false,
  "lease_duration": 2764800,
  "data": {
    "bar": "baz"
  },
  "wrap_info": null,
  "warnings": null,
  "auth": null
}
```

Успех!!!

### Use case использования авторизации через кубер

- Авторизуемся через vault-agent и получим клиентский токен
- Через consul-template достанем секрет и положим его в nginx
- Итог - nginx получил секрет из волта, не зная ничего про волт

### Заберем репозиторий с примерами

```console
git clone https://github.com/hashicorp/vault-guides.git
cd vault-guides/identity/vault-agent-k8s-demo
```

- В каталоге configs-k8s скорректируем конфиги с учетом ранее созданых ролей и секретов
- Проверим и скорректируем конфиг example-k8s-spec.yml

### Запускаем пример

```console
kubectl apply -f configmap.yaml
configmap/example-vault-agent-config created
```

```console
kubectl get configmap example-vault-agent-config -o yaml
apiVersion: v1
data:
  consul-template-config.hcl: |
    vault {
      renew_token = false
      vault_agent_token_file = "/home/vault/.vault-token"
      retry {
        backoff = "1s"
      }
    }

    template {
    destination = "/etc/secrets/index.html"
    contents = <<EOT
    <html>
    <body>
    <p>Some secrets:</p>
    {{- with secret "otus/otus-ro/config" }}
    <ul>
    <li><pre>username: {{ .Data.username }}</pre></li>
    <li><pre>password: {{ .Data.password }}</pre></li>
    </ul>
    {{ end }}
    </body>
    </html>
    EOT
    }
  vault-agent-config.hcl: |
    exit_after_auth = true

    pid_file = "/home/vault/pidfile"

    auto_auth {
        method "kubernetes" {
            mount_path = "auth/kubernetes"
            config = {
                role = "otus"
            }
        }

        sink "file" {
            config = {
                path = "/home/vault/.vault-token"
            }
        }
    }
kind: ConfigMap
metadata:
  annotations:
    kubectl.kubernetes.io/last-applied-configuration: |
      {"apiVersion":"v1","data":{"consul-template-config.hcl":"vault {\n  renew_token = false\n  vault_agent_token_file = \"/home/vault/.vault-token\"\n  retry {\n    backoff = \"1s\"\n  }\n}\n\ntemplate {\ndestination = \"/etc/secrets/index.html\"\ncontents = \u003c\u003cEOT\n\u003chtml\u003e\n\u003cbody\u003e\n\u003cp\u003eSome secrets:\u003c/p\u003e\n{{- with secret \"otus/otus-ro/config\" }}\n\u003cul\u003e\n\u003cli\u003e\u003cpre\u003eusername: {{ .Data.username }}\u003c/pre\u003e\u003c/li\u003e\n\u003cli\u003e\u003cpre\u003epassword: {{ .Data.password }}\u003c/pre\u003e\u003c/li\u003e\n\u003c/ul\u003e\n{{ end }}\n\u003c/body\u003e\n\u003c/html\u003e\nEOT\n}\n","vault-agent-config.hcl":"exit_after_auth = true\n\npid_file = \"/home/vault/pidfile\"\n\nauto_auth {\n    method \"kubernetes\" {\n        mount_path = \"auth/kubernetes\"\n        config = {\n            role = \"otus\"\n        }\n    }\n\n    sink \"file\" {\n        config = {\n            path = \"/home/vault/.vault-token\"\n        }\n    }\n}\n"},"kind":"ConfigMap","metadata":{"annotations":{},"name":"example-vault-agent-config","namespace":"default"}}
  creationTimestamp: "2020-06-16T16:20:41Z"
  name: example-vault-agent-config
  namespace: default
  resourceVersion: "603374"
  selfLink: /api/v1/namespaces/default/configmaps/example-vault-agent-config
  uid: 905b0e4b-b142-4d3b-a00c-7f1ef3eca0ba
```

```console
kubectl apply -f example-k8s-spec.yaml
pod/vault-agent-example created
```

### Проверим

- Законнектимся к поду nginx и вытащить оттуда index.html

```console
kubectl exec -ti vault-agent-example -c nginx-container  -- cat /usr/share/nginx/html/index.html
<html>
<body>
<p>Some secrets:</p>
<ul>
<li><pre>username: otus</pre></li>
<li><pre>password: asajkjkahs</pre></li>
</ul>

</body>
</html>
```

### Создадим CA на базе vault

- Включим pki секретс

```console
kubectl exec -it vault-0 -- vault secrets enable pki
Success! Enabled the pki secrets engine at: pki/

kubectl exec -it vault-0 -- vault secrets tune -max-lease-ttl=87600h pki
Success! Tuned the secrets engine at: pki/\

kubectl exec -it vault-0 -- vault write -field=certificate pki/root/generate/internal common_name="exmaple.ru" ttl=87600h > CA_cert.crt
```

### Пропишем урлы для ca и отозванных сертификатов

```console
kubectl exec -it vault-0 -- vault write pki/config/urls issuing_certificates="http://vault:8200/v1/pki/ca" crl_distribution_points="http://vault:8200/v1/pki/crl"
Success! Data written to: pki/config/urls
```

### Создадим промежуточный сертификат

kubectl exec -it vault-0 -- vault secrets enable --path=pki_int pki
Success! Enabled the pki secrets engine at: pki_int/

kubectl exec -it vault-0 -- vault secrets tune -max-lease-ttl=87600h pki_int
Success! Tuned the secrets engine at: pki_int/

kubectl exec -it vault-0 -- vault write -format=json pki_int/intermediate/generate/internal common_name="example.ru Intermediate Authority" | jq -r '.data.csr' > pki_intermediate.csr

### Пропишем промежуточный сертификат в vault

```console
kubectl cp pki_intermediate.csr vault-0:./tmp/

kubectl exec -it vault-0 -- vault write -format=json pki/root/sign-intermediate csr=@/tmp/pki_intermediate.csr format=pem_bundle ttl="43800h" | jq -r '.data.certificate' > intermediate.cert.pem

kubectl cp intermediate.cert.pem vault-0:./tmp/

kubectl exec -it vault-0 -- vault write pki_int/intermediate/set-signed certificate=@/tmp/intermediate.cert.pem
Success! Data written to: pki_int/intermediate/set-signed
```

### Создадим и отзовем новые сертификаты

- Создадим роль для выдачи сертификатов

```console
kubectl exec -it vault-0 -- vault write pki_int/roles/example-dot-ru \
allowed_domains="example.ru" allow_subdomains=true max_ttl="720h"

Success! Data written to: pki_int/roles/example-dot-ru
````

- Создадим сертификат

```console
kubectl exec -it vault-0 -- vault write pki_int/issue/example-dot-ru common_name="test.example.ru" ttl="24h"
Key                 Value
---                 -----
ca_chain            [-----BEGIN CERTIFICATE-----
MIIDnDCCAoSgAwIBAgIUbs1EMMtsCfGi2jGitWn72jXprjcwDQYJKoZIhvcNAQEL
BQAwFTETMBEGA1UEAxMKZXhtYXBsZS5ydTAeFw0yMDA2MTYxNjQzNDhaFw0yNTA2
MTUxNjQ0MThaMCwxKjAoBgNVBAMTIWV4YW1wbGUucnUgSW50ZXJtZWRpYXRlIEF1
dGhvcml0eTCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBALhxdC24BpMK
/tkUdItpGgxQsRpp7tTf/6o/RXCblZjHMKsHRhhAdW/Ww57jdCI91Sx30VR4dr6P
0dXLJ/c0VY7PyiH/91j5cmnJGj8fKIKodMei9vNdI+hYKoe4FNc/a1kfKEsUHfGf
QRr2ORwXmEMUyYros+DHUrYoeIMQP+8XJtQQjHCEByWYM6Tgpt4y6pzaRGN97yFs
UlMQmhyh7daRXKX/A4Tx1h/qhbCAjjGTtOKcssaWX6mu+uaY3zNVaWsbPgrL6erD
XEII8Ojh9Mx1StSKjwJfyOCJMVbY5t5xCZfYkOTXGOmuZ4mp3wj5ufgce21NQXwt
vujWMuPrZGECAwEAAaOBzDCByTAOBgNVHQ8BAf8EBAMCAQYwDwYDVR0TAQH/BAUw
AwEB/zAdBgNVHQ4EFgQUWRZvC2QKvzWdmOhtPRKElhpzywkwHwYDVR0jBBgwFoAU
6RO2+EqqFpHyVMR0ya+hy3a7nF4wNwYIKwYBBQUHAQEEKzApMCcGCCsGAQUFBzAC
hhtodHRwOi8vdmF1bHQ6ODIwMC92MS9wa2kvY2EwLQYDVR0fBCYwJDAioCCgHoYc
aHR0cDovL3ZhdWx0OjgyMDAvdjEvcGtpL2NybDANBgkqhkiG9w0BAQsFAAOCAQEA
cXHrM3Cji8lGKIn7O6CnnEnPiiyTxw7QTxJqBZJcGjL5SU/sqDp1cXXupRwHo7Gv
NdqM47HGGpixSekUGqjrlPdKX7/vylFGsh/F8MMOPhIXibBGASL3od+r5fhDVcdk
89Va80qpXx1rNfhphN3YrvNKj6DQSqh4dvlQNkJdj5v+65/vSK52aSilO8h7MIDd
RDc3Hew6dn5URDYueKHzcQ5rn0hg65W+9qeDhdRgcwz9GPJG0adC+RzJGlJE3GKN
aE4fj0ibnC6YJ++1GEPfAmkVuY7YUyUXNK1N3T1B4dzNFqeJ/Mr+pbIssGg9kQ2Z
DjHb8ySUM3JfZp2nQw5/iA==
-----END CERTIFICATE-----]
certificate         -----BEGIN CERTIFICATE-----
MIIDYzCCAkugAwIBAgIUU1UayYucW3SW43Etoz1kACntbucwDQYJKoZIhvcNAQEL
BQAwLDEqMCgGA1UEAxMhZXhhbXBsZS5ydSBJbnRlcm1lZGlhdGUgQXV0aG9yaXR5
MB4XDTIwMDYxNjE2NDg1MVoXDTIwMDYxNzE2NDkyMVowGjEYMBYGA1UEAxMPdGVz
dC5leGFtcGxlLnJ1MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAt+GI
RVjssgZgL240kXg+52zE9Yt6ToJI+gXs4wi7BSo68OJHGg8txN2lEOyMNx3Km64B
+Yxs3VGqXorMJgXcaYvbW+wgXFb+zqm6BN3jhVDiAOkmzJaaUtU0E6na/41olOX6
X1wLbkyU2bnV4K4J7KNjVXsGY0e0XZWu6nbfCy1vE5wtcrr8/9I723h6HW26g4cE
MPTXva2sTb/OBoPOozra/aPIYyJsgnPzNbC9SomqrSExXD7XyPzW6QsBOz3xotBZ
lQArT7GxK5BHBo2+Y94E7yGaGUKhfzjKDBVhOziAN3ZczUj/hlmIpB9+ptb140h3
dwuR8sOSQkZNP3XoPQIDAQABo4GOMIGLMA4GA1UdDwEB/wQEAwIDqDAdBgNVHSUE
FjAUBggrBgEFBQcDAQYIKwYBBQUHAwIwHQYDVR0OBBYEFOV6+X88HiFwdYKR6YER
bQWmXSxyMB8GA1UdIwQYMBaAFFkWbwtkCr81nZjobT0ShJYac8sJMBoGA1UdEQQT
MBGCD3Rlc3QuZXhhbXBsZS5ydTANBgkqhkiG9w0BAQsFAAOCAQEAF1E87BGiE67a
8bgbAmAMBZl4tY0XxB9NwO3fqCEVMvgxY4xT3SSQFVJPdN3ZOgOeCxtQ3k88lv0s
I9mZ44uZREDbLx9kMBfWpMwi3JsOjaSjwo/qMbyOUwOkkpSMtoBgolhsXii0PMe2
LRGZbEM4qCTgdgayVDvMUMA1zXUAaIrNRl3GHvWJiNCjtOYDyQFZ+Py+cTuogrPo
pHNAXrvM+ImnsNBHh9iWTN4MJP3rUHEZl4mb7ndy1s7YQjZxd6cCcX6m4fpt0m/e
tbobikyARh248etGSEaoUAjF+9WnMk1fihzRVRhpqV/W/Ix5wiDxfJXTFf7csZub
XZIV134kyg==
-----END CERTIFICATE-----
expiration          1592412561
issuing_ca          -----BEGIN CERTIFICATE-----
MIIDnDCCAoSgAwIBAgIUbs1EMMtsCfGi2jGitWn72jXprjcwDQYJKoZIhvcNAQEL
BQAwFTETMBEGA1UEAxMKZXhtYXBsZS5ydTAeFw0yMDA2MTYxNjQzNDhaFw0yNTA2
MTUxNjQ0MThaMCwxKjAoBgNVBAMTIWV4YW1wbGUucnUgSW50ZXJtZWRpYXRlIEF1
dGhvcml0eTCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBALhxdC24BpMK
/tkUdItpGgxQsRpp7tTf/6o/RXCblZjHMKsHRhhAdW/Ww57jdCI91Sx30VR4dr6P
0dXLJ/c0VY7PyiH/91j5cmnJGj8fKIKodMei9vNdI+hYKoe4FNc/a1kfKEsUHfGf
QRr2ORwXmEMUyYros+DHUrYoeIMQP+8XJtQQjHCEByWYM6Tgpt4y6pzaRGN97yFs
UlMQmhyh7daRXKX/A4Tx1h/qhbCAjjGTtOKcssaWX6mu+uaY3zNVaWsbPgrL6erD
XEII8Ojh9Mx1StSKjwJfyOCJMVbY5t5xCZfYkOTXGOmuZ4mp3wj5ufgce21NQXwt
vujWMuPrZGECAwEAAaOBzDCByTAOBgNVHQ8BAf8EBAMCAQYwDwYDVR0TAQH/BAUw
AwEB/zAdBgNVHQ4EFgQUWRZvC2QKvzWdmOhtPRKElhpzywkwHwYDVR0jBBgwFoAU
6RO2+EqqFpHyVMR0ya+hy3a7nF4wNwYIKwYBBQUHAQEEKzApMCcGCCsGAQUFBzAC
hhtodHRwOi8vdmF1bHQ6ODIwMC92MS9wa2kvY2EwLQYDVR0fBCYwJDAioCCgHoYc
aHR0cDovL3ZhdWx0OjgyMDAvdjEvcGtpL2NybDANBgkqhkiG9w0BAQsFAAOCAQEA
cXHrM3Cji8lGKIn7O6CnnEnPiiyTxw7QTxJqBZJcGjL5SU/sqDp1cXXupRwHo7Gv
NdqM47HGGpixSekUGqjrlPdKX7/vylFGsh/F8MMOPhIXibBGASL3od+r5fhDVcdk
89Va80qpXx1rNfhphN3YrvNKj6DQSqh4dvlQNkJdj5v+65/vSK52aSilO8h7MIDd
RDc3Hew6dn5URDYueKHzcQ5rn0hg65W+9qeDhdRgcwz9GPJG0adC+RzJGlJE3GKN
aE4fj0ibnC6YJ++1GEPfAmkVuY7YUyUXNK1N3T1B4dzNFqeJ/Mr+pbIssGg9kQ2Z
DjHb8ySUM3JfZp2nQw5/iA==
-----END CERTIFICATE-----
private_key         -----BEGIN RSA PRIVATE KEY-----
MIIEpAIBAAKCAQEAt+GIRVjssgZgL240kXg+52zE9Yt6ToJI+gXs4wi7BSo68OJH
Gg8txN2lEOyMNx3Km64B+Yxs3VGqXorMJgXcaYvbW+wgXFb+zqm6BN3jhVDiAOkm
zJaaUtU0E6na/41olOX6X1wLbkyU2bnV4K4J7KNjVXsGY0e0XZWu6nbfCy1vE5wt
crr8/9I723h6HW26g4cEMPTXva2sTb/OBoPOozra/aPIYyJsgnPzNbC9SomqrSEx
XD7XyPzW6QsBOz3xotBZlQArT7GxK5BHBo2+Y94E7yGaGUKhfzjKDBVhOziAN3Zc
zUj/hlmIpB9+ptb140h3dwuR8sOSQkZNP3XoPQIDAQABAoIBABXe8mllKUoHbhtW
HVSMG9dE3axi+Zoq7ukmGUXrvOrhWf9auqBD2+rFfiOkLw1DMt0PdlarOCue0gfK
tHt1SQEYzG+Dh1nUUxxbna+EgNJTi34WPTIqW5KsnzQTiOPKevzy2bPL6+QjobS/
4MuHh9CoomEBcAIQ/kf/TL3Ag8j9W8dEe/lFz6n2f7PnbXCWV0bQa7b2mc73F5sC
xWhATeR0QAKJtPUmgPuHNio1+vvVYu62ulEEJgxRrwcqejSAJyRbNi4qPnwzN0nI
x4MEFlzuF7V21oGkovlMPwLybnFSQ+A4FGaiBObEb6IxSRHh2CYwP/t74efiQvzD
gVNwYDUCgYEA4lJDO1C2XOc2ANvrACYEVwXl6+ZVQOwZTN2sMDa4+T/6MQu8ED3j
3LQ4NrQUv5CSsi0ru3g/uIbIZmsVl9KVdWibBiflH3XcGK0Gmuydj26+32sMn1IL
B1cPl4ovlFjDB82D/w8jirdp5bcrAhZhys7uKnaglzaWTxURioG4RqMCgYEAz/6F
zKsr5+2VHWUPx8zsAQbRhNH8aCpBTDjbisuyVDrR6CdhafRUAL8nFs6E/uHKFX7i
3wZdzV6F6G8yON6laO7CdhgyPnH3X6VBeg64NX4OV/E6tyyo+9zZFiinD2Wa1mxg
4/nF1kGblOoZuGVnvCwmVv6EfAo8V0ZYuCKbY58CgYEA3sZWw4Y5W82DjOjss2K4
luiJX+GEPbmpVc5F9deH0GE3ZxvD7MDfEJqdUsuEOOSYYaaxC4HcR0j07kuuH5n7
4GwtXKvcj1E2a1u1yr3qggti+wymihT6IimCgYpWN1H/+ChGK8S9GYhdRu87+HwL
mtSB/25xuSbUYde9QndZ6r0CgYBw1MIApVrMFjYuHATTfncIl4pRYxhp6YJCtxVh
1d6HkuEL71EJCWIIhanO1XmQSyw1PQAVvH5mSkCaNrgn4aAZrGwRZE7dUTXAzQUY
EaQcYKWnT1VqyO9isguR2bvGvnegmmp1Qanw8OZVgikxvtDnY4vo5Wk5YNQbBC5c
tWlWQQKBgQCc77OYAbK6STzcnq3Y5lbGEbPilsZFW9j4mJueOdIJ+zVABagjcdRj
O2ES9nYeeE2H9026Z4KFhCwH3EXEsuDNBDAOiJtt2G9Jyd2uHfsp5J/m7BIKo9Sa
qdWT93qzqGlKeeqeO9M60kupzxJ+piAR4R0TpiS4FnL4qJLnL70now==
-----END RSA PRIVATE KEY-----
private_key_type    rsa
serial_number       53:55:1a:c9:8b:9c:5b:74:96:e3:71:2d:a3:3d:64:00:29:ed:6e:e7
```

- Отзовем сертификат

```console
kubectl exec -it vault-0 -- vault write pki_int/revoke serial_number="53:55:1a:c9:8b:9c:5b:74:96:e3:71:2d:a3:3d:64:00:29:ed:6e:e7"
Key                        Value
---                        -----
revocation_time            1592326196
revocation_time_rfc3339    2020-06-16T16:49:56.117712099Z
```

### Включим TLS

Реализуем доступ к vault через https с CA из кубернетес

- Создим CSR

```console
openssl genrsa -out vault_gke.key 4096
```

vault_gke_csr.cnf

```console
[ req ]
default_bits = 2048
prompt = no
default_md = sha256
distinguished_name = dn
req_extensions = v3_ext
[ dn ]
commonName = localhost
stateOrProvinceName = Moscow
countryName = RU
emailAddress = lucky@perflabs.org
organizationName = Perflabs
organizationalUnitName = Development
[ v3_ext ]
basicConstraints = CA:FALSE
keyUsage = keyEncipherment,dataEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names
[alt_names]
DNS.0 = localhost
DNS.1 = vault
```

```console
openssl req -config vault_gke_csr.cnf -new -key vault_gke.key -nodes -out vault.csr
```

openssl req -config vault_gke_csr.cnf -new -key vault_gke.key -nodes -out vault.csr

vault_csr.yaml

```yml
apiVersion: certificates.k8s.io/v1beta1
kind: CertificateSigningRequest
metadata:
  name: vaultcsr
spec:
  groups:
  - system:authenticated
  request: $(base64 < "vault.csr" | tr -d '\n')
  usages:
  - digital signature
  - key encipherment
  - server auth
```

- Применим

```console
kubectl apply -f vault_csr.yaml
certificatesigningrequest.certificates.k8s.io/vaultcsr created

kubectl certificate approve vaultcsr
certificatesigningrequest.certificates.k8s.io/vaultcsr approved

kubectl get csr vaultcsr -o jsonpath='{.status.certificate}' | base64 --decode > vault.crt

kubectl create secret tls vault-certs --cert=vault.crt --key=vault_gke.key
```

Пересоздадим vault с новым vault-tls.values.yaml

```console
helm upgrade --install vault hashicorp/vault -f vault-tls.values.yaml
Release "vault" does not exist. Installing it now.
NAME: vault
LAST DEPLOYED: Tue Jun 16 23:56:52 2020
NAMESPACE: default
STATUS: deployed
REVISION: 1
TEST SUITE: None
NOTES:
Thank you for installing HashiCorp Vault!

Now that you have deployed Vault, you should look over the docs on using
Vault with Kubernetes available here:

https://www.vaultproject.io/docs/


Your release is named vault. To learn more about the release, try:

  $ helm status vault
  $ helm get vault
```

Проверяем:

```console
kubectl get secret $(kubectl get sa vault-auth -o jsonpath="{.secrets[*]['name']}") -o jsonpath="{.data['ca\.crt']}" | base64 --decode  > ca.crt

kubectl port-forward vault-0 8200:8200

curl --cacert ca.crt  -H "X-Vault-Token: s.Q4JOojZtdGgfiwoxJ4L3v75w" -X GET https://localhost:8200/v1/otus/otus-ro/config | jq
{
  "request_id": "ecda370b-4696-43b5-d7ad-158736974806",
  "lease_id": "",
  "renewable": false,
  "lease_duration": 2764800,
  "data": {
    "password": "asajkjkahs",
    "username": "otus"
  },
  "wrap_info": null,
  "warnings": null,
  "auth": null
}
```

## Сервисы централизованного логирования для компонентов Kubernetes и приложений

### Подготовка Kubernetes кластера

Для выполнения домашнего задания нам понадобится managed Kubernetes кластер в GCP:

- Как минимум 1 нода типа n1-standard-2 в default-pool
- Как минимум 3 ноды типа n1-standard-2 в infra-pool

Так как мы будем использовать свои инструменты для логирования, важно отключить Stackdriver, компоненты которого устанавливаются по умолчанию при создании GKE кластера.

> Если этого не сделать, существует ненулевая вероятность конфликта между Fluentd, устанавливаемым как часть решения Stackdriver, и Fluent Bit

Как можно догадаться из названия, мы планируем отдать три из четырех нод кластера под инфраструктурные сервисы.  
Присвоим этим нодам определенный , чтобы избежать запуска на них случайных pod.  
Укажем следующую конфигурацию [taint](https://kubernetes.io/docs/concepts/configuration/taint-and-toleration/) через web-интерфейс GCP: **node-role=infra:NoSchedule**

В результате должна получиться следующая конфигурация кластера:

```console
kubectl get nodes

NAME                                       STATUS   ROLES    AGE     VERSION
gke-cluster-1-default-pool-77d8d79a-rltz   Ready    <none>   15m     v1.16.9-gke.2
gke-cluster-1-infra-pool-f025c03e-btq7     Ready    <none>   7m32s   v1.16.9-gke.2
gke-cluster-1-infra-pool-f025c03e-c1t3     Ready    <none>   7m33s   v1.16.9-gke.2
gke-cluster-1-infra-pool-f025c03e-lbf4     Ready    <none>   7m32s   v1.16.9-gke.2
```

### Установка HipsterShop

Для начала, установим в Kubernetes кластер уже знакомый нам HipsterShop.

Самый простой способ сделать это - применить подготовленный манифест:

```console
kubectl create ns microservices-demo
namespace/microservices-demo created

kubectl apply -f https://raw.githubusercontent.com/express42/otus-platform-snippets/master/Module-02/Logging/microservices-demo-without-resources.yaml -n microservices-demo
deployment.apps/emailservice created
service/emailservice created
deployment.apps/checkoutservice created
service/checkoutservice created
deployment.apps/recommendationservice created
service/recommendationservice created
deployment.apps/frontend created
service/frontend created
service/frontend-external created
deployment.apps/paymentservice created
service/paymentservice created
deployment.apps/productcatalogservice created
service/productcatalogservice created
deployment.apps/cartservice created
service/cartservice created
deployment.apps/loadgenerator created
deployment.apps/currencyservice created
service/currencyservice created
deployment.apps/shippingservice created
service/shippingservice created
deployment.apps/redis-cart created
service/redis-cart created
deployment.apps/adservice created
service/adservice created
```

Проверим, что все pod развернулись на ноде из default-pool:

```console
kubectl get pods -n microservices-demo -o wide

NAME                                     READY   STATUS    RESTARTS   AGE     IP           NODE                                       NOMINATED NODE   READINESS GATES
adservice-cb695c556-97r7f                1/1     Running   0          5m16s   10.60.0.19   gke-cluster-1-default-pool-77d8d79a-rltz   <none>           <none>
cartservice-f4677b75f-tbkmj              1/1     Running   2          5m18s   10.60.0.14   gke-cluster-1-default-pool-77d8d79a-rltz   <none>           <none>
checkoutservice-664f865b9b-gv8pp         1/1     Running   0          5m19s   10.60.0.10   gke-cluster-1-default-pool-77d8d79a-rltz   <none>           <none>
currencyservice-bb9d998bd-xcjcs          1/1     Running   0          5m17s   10.60.0.15   gke-cluster-1-default-pool-77d8d79a-rltz   <none>           <none>
emailservice-6756967b6d-znhwj            1/1     Running   0          5m19s   10.60.0.8    gke-cluster-1-default-pool-77d8d79a-rltz   <none>           <none>
frontend-766587959d-vwfxm                1/1     Running   0          5m19s   10.60.0.11   gke-cluster-1-default-pool-77d8d79a-rltz   <none>           <none>
loadgenerator-9f854cfc5-brhm8            1/1     Running   4          5m17s   10.60.0.17   gke-cluster-1-default-pool-77d8d79a-rltz   <none>           <none>
paymentservice-57c87dc78b-zch9w          1/1     Running   0          5m18s   10.60.0.12   gke-cluster-1-default-pool-77d8d79a-rltz   <none>           <none>
productcatalogservice-9f5d68b54-zrbqt    1/1     Running   0          5m18s   10.60.0.13   gke-cluster-1-default-pool-77d8d79a-rltz   <none>           <none>
recommendationservice-57c49756fd-lcq6s   1/1     Running   0          5m19s   10.60.0.9    gke-cluster-1-default-pool-77d8d79a-rltz   <none>           <none>
redis-cart-5f75fbd9c7-9mfck              1/1     Running   0          5m16s   10.60.0.18   gke-cluster-1-default-pool-77d8d79a-rltz   <none>           <none>
shippingservice-689c6457cd-sbp55         1/1     Running   0          5m17s   10.60.0.16   gke-cluster-1-default-pool-77d8d79a-rltz   <none>           <none>
```

### Установка EFK стека | Helm charts

В данном домашнем задании мы будет устанавливать и использовать различные решения для логирования различными способами.

Начнем с "классического" набора инструментов (**ElasticSearch, Fluent Bit, Kibana**) и "классического" способа его установки в Kubernetes кластер (**Helm**).

Рекомендуемый репозиторий с Helm chart для ElasticSearch и Kibana на текущий момент - <https://github.com/elastic/helm-charts>.

Добавим его:

```console
helm repo add elastic https://helm.elastic.co
"elastic" has been added to your repositories
```

И установим нужные нам компоненты, для начала - без какой либо дополнительной настройки:

ElasticSearch:

```console
helm upgrade --install elasticsearch elastic/elasticsearch --namespace observability
Release "elasticsearch" does not exist. Installing it now.
NAME: elasticsearch
LAST DEPLOYED: Fri Jun  5 11:54:41 2020
NAMESPACE: observability
STATUS: deployed
REVISION: 1
NOTES:
1. Watch all cluster members come up.
  $ kubectl get pods --namespace=observability -l app=elasticsearch-master -w
2. Test cluster health using Helm test.
  $ helm test elasticsearch --cleanup
```

Kibana

```console
helm upgrade --install kibana elastic/kibana --namespace observability
Release "kibana" does not exist. Installing it now.
NAME: kibana
LAST DEPLOYED: Fri Jun  5 11:55:16 2020
NAMESPACE: observability
STATUS: deployed
REVISION: 1
TEST SUITE: None
```

Fluent Bit

```console
helm upgrade --install fluent-bit stable/fluent-bit --namespace observability
Release "fluent-bit" does not exist. Installing it now.
NAME: fluent-bit
LAST DEPLOYED: Fri Jun  5 11:57:47 2020
NAMESPACE: observability
STATUS: deployed
REVISION: 1
NOTES:
fluent-bit is now running.

It will forward all container logs to the svc named fluentd on port: 24284
```

```console
kubectl get pods -n observability  -o wide
NAME                            READY   STATUS    RESTARTS   AGE     IP           NODE                                       NOMINATED NODE   READINESS GATES
elasticsearch-master-0          0/1     Pending   0          3m41s   <none>       <none>                                     <none>           <none>
elasticsearch-master-1          0/1     Pending   0          3m41s   <none>       <none>                                     <none>           <none>
elasticsearch-master-2          0/1     Running   0          3m41s   10.60.0.20   gke-cluster-1-default-pool-77d8d79a-rltz   <none>           <none>
fluent-bit-j845q                1/1     Running   0          34s     10.60.0.21   gke-cluster-1-default-pool-77d8d79a-rltz   <none>           <none>
kibana-kibana-869dfc7ff-kvjl9   0/1     Pending   0          3m6s    <none>       <none>                                     <none>           <none>
```

Если посмотреть, как установленные нами сервисы распределились по нодам, можно догадаться, что что-то пошло не по плану, все сервисы с переменным успехом попытались запуститься только на одной ноде из default-pool.

Попробуем исправить это и запустить каждую реплику ElasticSearch на своей, выделенной ноде из infra-pool.

Создадим в директории kubernetes-logging файл elasticsearch.values.yaml, будем указывать в этом файле нужные нам values.

Для начала, обратимся к файлу values.yaml в [репозитории](https://github.com/elastic/helm-charts/blob/master/elasticsearch) и найдем там ключ tolerations.  
Мы помним, что ноды из infra-pool имеют taint node-role=infra:NoSchedule.  
Давайте разрешим ElasticSearch запускаться на данных нодах:

```yml
tolerations:
  - key: node-role
    operator: Equal
    value: infra
    effect: NoSchedule
```

Обновим установку:

```console
helm upgrade --install elasticsearch elastic/elasticsearch --namespace observability -f elasticsearch.values.yaml
Release "elasticsearch" has been upgraded. Happy Helming!
NAME: elasticsearch
LAST DEPLOYED: Sat Jun  6 11:59:11 2020
NAMESPACE: observability
STATUS: deployed
REVISION: 2
NOTES:
1. Watch all cluster members come up.
  $ kubectl get pods --namespace=observability -l app=elasticsearch-master -w
2. Test cluster health using Helm test.
  $ helm test elasticsearch --cleanup
```

Теперь ElasticSearch **может** запускаться на нодах из infra-pool, но это не означает, что он **должен** это делать.  
Исправим этот момент и добавим в elasticsearch.values.yaml NodeSelector, определяющий, на каких нодах мы можем запускать наши pod.

```yml
nodeSelector:
  cloud.google.com/gke-nodepool: infra-pool
```

> Другой, и, на самом деле, более гибкий способ осуществить задуманное - nodeAffinity

```console
helm upgrade --install elasticsearch elastic/elasticsearch --namespace observability -f elasticsearch.values.yaml
Release "elasticsearch" has been upgraded. Happy Helming!
NAME: elasticsearch
LAST DEPLOYED: Sat Jun  6 12:02:43 2020
NAMESPACE: observability
STATUS: deployed
REVISION: 3
NOTES:
1. Watch all cluster members come up.
  $ kubectl get pods --namespace=observability -l app=elasticsearch-master -w
2. Test cluster health using Helm test.
```

Если все выполнено корректно, то через некоторое время мы сможем наблюдать следующую картину:

```console
kubectl get pods -n observability -o wide -l chart=elasticsearch
NAME                     READY   STATUS    RESTARTS   AGE     IP          NODE                                     NOMINATED NODE   READINESS GATES
elasticsearch-master-0   1/1     Running   0          4m42s   10.60.1.2   gke-cluster-1-infra-pool-f025c03e-btq7   <none>           <none>
elasticsearch-master-1   1/1     Running   0          6m5s    10.60.3.3   gke-cluster-1-infra-pool-f025c03e-c1t3   <none>           <none>
elasticsearch-master-2   1/1     Running   0          7m34s   10.60.2.3   gke-cluster-1-infra-pool-f025c03e-lbf4   <none>           <none>
```

Пока остановимся на этом и перейдем к следующему компоненту инсталляции.

### Установка nginx-ingress

Для того, чтобы продолжить установку EFK стека и получить доступ к Kibana, предварительно потребуется развернуть ingress-controller.

Установим nginx-ingress, состоящий из трех реплик controller, по одной, на каждую ноду из infra-pool.

Подготовим ingress.values.yaml

```yml
controller:
  replicaCount: 3

  tolerations:
    - key: node-role
      operator: Equal
      value: infra
      effect: NoSchedule

  affinity:
    podAntiAffinity:
      preferredDuringSchedulingIgnoredDuringExecution:
      - weight: 100
        podAffinityTerm:
          labelSelector:
            matchExpressions:
            - key: app
              operator: In
              values:
              - nginx-ingress
          topologyKey: kubernetes.io/hostname

  nodeSelector:
    cloud.google.com/gke-nodepool: infra-pool
```

Развернем:

```console
helm upgrade --install nginx-ingress stable/nginx-ingress --wait \
--namespace=nginx-ingress \
--version=1.39.0 -f nginx-ingress.values.yaml --create-namespace
Release "nginx-ingress" does not exist. Installing it now.
NAME: nginx-ingress
LAST DEPLOYED: Sat Jun  6 12:14:24 2020
NAMESPACE: nginx-ingress
STATUS: deployed
REVISION: 1
TEST SUITE: None
NOTES:
The nginx-ingress controller has been installed.
It may take a few minutes for the LoadBalancer IP to be available.
You can watch the status by running 'kubectl --namespace nginx-ingress get services -o wide -w nginx-ingress-controller'

An example Ingress that makes use of the controller:

  apiVersion: extensions/v1beta1
  kind: Ingress
  metadata:
    annotations:
      kubernetes.io/ingress.class: nginx
    name: example
    namespace: foo
  spec:
    rules:
      - host: www.example.com
        http:
          paths:
            - backend:
                serviceName: exampleService
                servicePort: 80
              path: /
    # This section is only required if TLS is to be enabled for the Ingress
    tls:
        - hosts:
            - www.example.com
          secretName: example-tls

If TLS is enabled for the Ingress, a Secret containing the certificate and key must also be provided:

  apiVersion: v1
  kind: Secret
  metadata:
    name: example-tls
    namespace: foo
  data:
    tls.crt: <base64 encoded cert>
    tls.key: <base64 encoded key>
  type: kubernetes.io/tls
```

```console
kubectl get pods -n nginx-ingress
NAME                                             READY   STATUS    RESTARTS   AGE
nginx-ingress-controller-64c77ff77-g7vgr         1/1     Running   0          3m53s
nginx-ingress-controller-64c77ff77-r9v6p         1/1     Running   0          3m53s
nginx-ingress-controller-64c77ff77-z4rpp         1/1     Running   0          3m53s
nginx-ingress-default-backend-5b967cf596-7pckn   1/1     Running   0          3m53s
```

### Установка EFK стека | Kibana

По традиции создадим файл kibana.values.yaml в директории kubernetes-logging и добавим туда конфигурацию для создания ingress:

```yml
ingress:
  enabled: true
  annotations: {
    kubernetes.io/ingress.class: nginx
  }
  path: /
  hosts:
    - kibana.35.205.196.95.xip.io
```

Обновим релиз:

```console
helm upgrade --install kibana elastic/kibana --namespace observability -f kibana.values.yaml
Release "kibana" has been upgraded. Happy Helming!
NAME: kibana
LAST DEPLOYED: Sat Jun  6 12:27:19 2020
NAMESPACE: observability
STATUS: deployed
REVISION: 2
TEST SUITE: None
```

### Установка EFK стека

После прохождения всех предыдущих шагов у вас должен появиться доступ к Kibana по URL **kibana.35.205.196.95.xip.io**  

Попробуем создать index pattern, и увидим, что в ElasticSearch пока что не обнаружено никаких данных.

Посмотрим в логи решения, которое отвечает за отправку логов (Fluent Bit) и увидим следующие строки:

```console
kubectl logs fluent-bit-j845q  -n observability --tail 3
[2020/06/06 09:29:24] [ warn] net_tcp_fd_connect: getaddrinfo(host='fluentd'): Name or service not known
[2020/06/06 09:29:24] [error] [out_fw] no upstream connections available
[2020/06/06 09:29:24] [ warn] [engine] failed to flush chunk '1-1591347474.564902547.flb', retry in 1581 seconds: task_id=18, input=tail.0 > output=forward.0
```

Попробуем исправить проблему. Создадим файл fluentbit.values.yaml и добавим туда:

```yml
backend:
  type: es
  es:
    host: elasticsearch-master
```

> Описание того, что мы сделали, можно найти в [документации](https://fluentbit.io/documentation/0.13/output/elasticsearch.html) и в оригинальном файле [values](https://github.com/helm/charts/blob/master/stable/fluent-bit/values.yaml)

```console
helm upgrade --install fluent-bit stable/fluent-bit --namespace observability -f fluent-bit.values.yaml
Release "fluent-bit" has been upgraded. Happy Helming!
NAME: fluent-bit
LAST DEPLOYED: Sat Jun  6 12:31:46 2020
NAMESPACE: observability
STATUS: deployed
REVISION: 2
NOTES:
fluent-bit is now running.

It will forward all container logs to the svc named elasticsearch-master on port: 9200
```

Попробуем повторно создать index pattern. В этот раз ситуация изменилась, и какие-то индексы в ElasticSearch уже ест.

После установки можно заметить, что в ElasticSearch попадают далеко не все логи нашего приложения.

Причину можно найти в логах pod с Fluent Bit, он пытается обработать JSON, отдаваемый приложением, и находит там дублирующиеся поля **time** и **timestamp**

> GitHub [issue](https://github.com/fluent/fluent-bit/issues/628), с более подробным описанием проблемы

Вариантов решения проблемы, озвученной ранее, несколько:

- Полностью отключить парсинг JSON внутри лога ключом filter.mergeJSONLog=false
- Складывать содержимое лога после парсинга в отдельный ключ (в нашем случае для некоторых микросервисов возникнет проблема illegal_argument_exception с полем time)
- Изменить имя ключа (time_key) с датой, добавляемое самим Fluent Bit, на что-то, отличное от @timestamp. Это не решит проблему с тем, что останется поле time, которое также будет помечено дублирующимся
- "Вырезать" из логов поля time и @timestamp

Мы пойдем сложным путем и воспользуемся фильтром, который позволит удалить из логов "лишние" ключи

Пример итогового fluent-bit.values.yaml:

```yml
rawConfig: |
  @INCLUDE fluent-bit-service.conf
  @INCLUDE fluent-bit-input.conf
  @INCLUDE fluent-bit-filter.conf
  @INCLUDE fluent-bit-output.conf

  [FILTER]
      Name modify
      Match *
      Remove time
      Remove @timestamp
```

Обновим:

```console
helm upgrade --install fluent-bit stable/fluent-bit --namespace observability -f fluent-bit.values.yaml
Release "fluent-bit" has been upgraded. Happy Helming!
NAME: fluent-bit
LAST DEPLOYED: Sat Jun  6 12:44:32 2020
NAMESPACE: observability
STATUS: deployed
REVISION: 3
NOTES:
fluent-bit is now running.

It will forward all container logs to the svc named elasticsearch-master on port: 9200
```

Установка EFK стека | Задание со ⭐

Для решения проблемы с дублирующими полями изменим наш fluent-bit.values.yaml:

- Уберем секцию удаления полей time и timestamp
- Добавим **mergeLogKey: "app"** - это добавление префикса к полям из json

```yml
filter:
    mergeLogKey: "app"
```

### Мониторинг ElasticSearch

Помимо установки ElasticSearch, важно отслеживать его показатели и вовремя понимать, что пора предпринять какие-либо
действия. Для мониторинга ElasticSearch будем использовать следующий [Prometheus exporter](https://github.com/justwatchcom/elasticsearch_exporter)

- Установим prometheus-operator в namespace observability

```yml
prometheus:
  ingress:
      enabled: true
      annotations: {
        kubernetes.io/ingress.class: nginx
      }
      path: /
      hosts:
        - prometheus.35.205.196.95.xip.io
  prometheusSpec:
    tolerations:
    - key: node-role
      operator: Equal
      value: infra
      effect: NoSchedule
    serviceMonitorSelectorNilUsesHelmValues: false
grafana:
  ingress:
      enabled: true
      annotations: {
        kubernetes.io/ingress.class: nginx
      }
      path: /
      hosts:
        - grafana.35.205.196.95.xip.io
```

```console
helm upgrade --install  prometheus-operator stable/prometheus-operator -n observability --create-namespace -f prometheus.values.yaml
Release "prometheus-operator" does not exist. Installing it now.
manifest_sorter.go:192: info: skipping unknown hook: "crd-install"
manifest_sorter.go:192: info: skipping unknown hook: "crd-install"
manifest_sorter.go:192: info: skipping unknown hook: "crd-install"
manifest_sorter.go:192: info: skipping unknown hook: "crd-install"
manifest_sorter.go:192: info: skipping unknown hook: "crd-install"
manifest_sorter.go:192: info: skipping unknown hook: "crd-install"
NAME: prometheus-operator
LAST DEPLOYED: Sat Jun  6 12:47:46 2020
NAMESPACE: observability
STATUS: deployed
REVISION: 1
NOTES:
The Prometheus Operator has been installed. Check its status by running:
  kubectl --namespace observability get pods -l "release=prometheus-operator"

Visit https://github.com/coreos/prometheus-operator for instructions on how
to create & configure Alertmanager and Prometheus instances using the Operator.
```

- Установим prometheus exporter

```console
helm upgrade --install elasticsearch-exporter stable/elasticsearch-exporter --set es.uri=http://elasticsearch-master:9200 --set serviceMonitor.enabled=true --namespace=observability

Release "elasticsearch-exporter" does not exist. Installing it now.
NAME: elasticsearch-exporter
LAST DEPLOYED: Sat Jun  6 12:54:01 2020
NAMESPACE: observability
STATUS: deployed
REVISION: 1
TEST SUITE: None
NOTES:
1. Get the application URL by running these commands:
  export POD_NAME=$(kubectl get pods --namespace observability -l "app=elasticsearch-exporter" -o jsonpath="{.items[0].metadata.name}")
  echo "Visit http://127.0.0.1:9108/metrics to use your application"
  kubectl port-forward $POD_NAME 9108:9108 --namespace observability
```

Импортируем в Grafana один из популярных [Dashboard](https://grafana.com/grafana/dashboards/4358) для ElasticSearch exporter, содержащий визуализацию основных собираемых метрик.

Проверим, что метрики действительно собираются корректно.  
Сделаем drain одной из нод infra-pool: kubectl drain <NODE_NAME> --ignore-daemonsets

```console
kubectl get nodes
NAME                                       STATUS   ROLES    AGE   VERSION
gke-cluster-1-default-pool-77d8d79a-rltz   Ready    <none>   39h   v1.16.9-gke.2
gke-cluster-1-infra-pool-f025c03e-btq7     Ready    <none>   39h   v1.16.9-gke.2
gke-cluster-1-infra-pool-f025c03e-c1t3     Ready    <none>   39h   v1.16.9-gke.2
gke-cluster-1-infra-pool-f025c03e-lbf4     Ready    <none>   39h   v1.16.9-gke.2

kubectl drain gke-cluster-1-infra-pool-f025c03e-c1t3 --ignore-daemonsets
node/gke-cluster-1-infra-pool-f025c03e-c1t3 cordoned
WARNING: ignoring DaemonSet-managed Pods: observability/prometheus-operator-prometheus-node-exporter-w4ljx
evicting pod "elasticsearch-master-1"
evicting pod "nginx-ingress-controller-64c77ff77-r9v6p"
pod/elasticsearch-master-1 evicted
pod/nginx-ingress-controller-64c77ff77-r9v6p evicted
node/gke-cluster-1-infra-pool-f025c03e-c1t3 evicted

kubectl get pods -n observability
NAME                                                      READY   STATUS    RESTARTS   AGE
alertmanager-prometheus-operator-alertmanager-0           2/2     Running   0          52m
elasticsearch-exporter-65d6647f8b-9gw76                   1/1     Running   0          117m
elasticsearch-master-0                                    1/1     Running   0          165m
elasticsearch-master-1                                    0/1     Pending   0          59s
elasticsearch-master-2                                    1/1     Running   0          168m
fluent-bit-9fjhk                                          1/1     Running   0          126m
kibana-kibana-869dfc7ff-kvjl9                             1/1     Running   0          26h
prometheus-operator-grafana-6567c8ff97-46hn8              2/2     Running   0          52m
prometheus-operator-kube-state-metrics-7f979567df-cwpzf   1/1     Running   0          52m
prometheus-operator-operator-874c49dfb-jqkbr              2/2     Running   0          34m
prometheus-operator-prometheus-node-exporter-7mjxz        1/1     Running   0          49m
prometheus-operator-prometheus-node-exporter-gmpfw        1/1     Running   0          49m
prometheus-operator-prometheus-node-exporter-r68t4        1/1     Running   0          49m
prometheus-operator-prometheus-node-exporter-w4ljx        1/1     Running   0          49m
prometheus-prometheus-operator-prometheus-0               3/3     Running   1          18m
```

Статус Cluster Health остался зеленым, но количество нод в кластере уменьшилось до двух штук. При этом, кластер сохранил полную работоспособность.

Попробуем сделать drain второй ноды из infra-pool, и увидим что не дает этого сделать.

```console
kubectl drain gke-cluster-1-infra-pool-f025c03e-lbf4    --ignore-daemonsets
node/gke-cluster-1-infra-pool-f025c03e-lbf4 cordoned
error: unable to drain node "gke-cluster-1-infra-pool-f025c03e-lbf4", aborting command...

There are pending nodes to be drained:
 gke-cluster-1-infra-pool-f025c03e-lbf4
error: cannot delete Pods with local storage (use --delete-local-data to override): observability/prometheus-prometheus-operator-prometheus-0
```

Вручную удалим pod, находящийся на ноде, для которой мы пытались сделать drain:

```console
kubectl delete pod elasticsearch-master-2 -n observability
pod "elasticsearch-master-2" deleted

kubectl get pods -n observability -o wide
NAME                                                      READY   STATUS    RESTARTS   AGE     IP            NODE                                       NOMINATED NODE   READINESS GATES
alertmanager-prometheus-operator-alertmanager-0           2/2     Running   0          58m     10.60.0.44    gke-cluster-1-default-pool-77d8d79a-rltz   <none>           <none>
elasticsearch-exporter-65d6647f8b-9gw76                   1/1     Running   0          123m    10.60.0.33    gke-cluster-1-default-pool-77d8d79a-rltz   <none>           <none>
elasticsearch-master-0                                    1/1     Running   0          172m    10.60.1.2     gke-cluster-1-infra-pool-f025c03e-btq7     <none>           <none>
elasticsearch-master-1                                    0/1     Pending   0          7m12s   <none>        <none>                                     <none>           <none>
elasticsearch-master-2                                    0/1     Pending   0          33s     <none>        <none>                                     <none>           <none>
fluent-bit-9fjhk                                          1/1     Running   0          133m    10.60.0.26    gke-cluster-1-default-pool-77d8d79a-rltz   <none>           <none>
kibana-kibana-869dfc7ff-kvjl9                             1/1     Running   0          27h     10.60.0.23    gke-cluster-1-default-pool-77d8d79a-rltz   <none>           <none>
prometheus-operator-grafana-6567c8ff97-46hn8              2/2     Running   0          58m     10.60.0.42    gke-cluster-1-default-pool-77d8d79a-rltz   <none>           <none>
prometheus-operator-kube-state-metrics-7f979567df-cwpzf   1/1     Running   0          58m     10.60.0.41    gke-cluster-1-default-pool-77d8d79a-rltz   <none>           <none>
prometheus-operator-operator-874c49dfb-jqkbr              2/2     Running   0          40m     10.60.0.56    gke-cluster-1-default-pool-77d8d79a-rltz   <none>           <none>
prometheus-operator-prometheus-node-exporter-7mjxz        1/1     Running   0          55m     10.132.0.9    gke-cluster-1-infra-pool-f025c03e-btq7     <none>           <none>
prometheus-operator-prometheus-node-exporter-gmpfw        1/1     Running   0          55m     10.132.0.8    gke-cluster-1-default-pool-77d8d79a-rltz   <none>           <none>
prometheus-operator-prometheus-node-exporter-r68t4        1/1     Running   0          55m     10.132.0.10   gke-cluster-1-infra-pool-f025c03e-lbf4     <none>           <none>
prometheus-operator-prometheus-node-exporter-w4ljx        1/1     Running   0          55m     10.132.0.11   gke-cluster-1-infra-pool-f025c03e-c1t3     <none>           <none>
prometheus-prometheus-operator-prometheus-0               3/3     Running   1          25m     10.60.2.6     gke-cluster-1-infra-pool-f025c03e-lbf4     <none>           <none>

kubectl get nodes
NAME                                       STATUS                     ROLES    AGE   VERSION
gke-cluster-1-default-pool-77d8d79a-rltz   Ready                      <none>   39h   v1.16.9-gke.2
gke-cluster-1-infra-pool-f025c03e-btq7     Ready                      <none>   39h   v1.16.9-gke.2
gke-cluster-1-infra-pool-f025c03e-c1t3     Ready,SchedulingDisabled   <none>   39h   v1.16.9-gke.2
gke-cluster-1-infra-pool-f025c03e-lbf4     Ready,SchedulingDisabled   <none>   39h   v1.16.9-gke.2\
```

После данного действия можно заметить следующее:

- Оставшийся pod с ElasticSearch перешел в статус "Not Ready"
- Kibana потеряла подключение к кластеру
- Метрики Prometheus перестали собираться, так как у сервиса, к которому подключается exporter, пропали все endpoint

Сделаем вывод - узнавать о проблемах с ElasticSearch в нашем сценарии (**replication factor = 1: 1 shard + 1 replica** на индекс) желательно на этапе выхода из строя первой ноды в кластере.

В определении проблем с участниками кластера ElasticSearch может помочь следующий Prometheus alert [источник](https://github.com/justwatchcom/elasticsearch_exporter/blob/master/examples/prometheus/elasticsearch.rules).

```console
ALERT ElasticsearchTooFewNodesRunning
  IF elasticsearch_cluster_health_number_of_nodes < 3
  FOR 5m
  LABELS {severity="critical"}
  ANNOTATIONS {description="There are only {{$value}} < 3 ElasticSearch nodes running", summary="ElasticSearch running on less than 3 nodes"}
```

Ввернем ноды в строй (kubectl uncordon <NODE_NAME>)

```console
kubectl uncordon gke-cluster-1-infra-pool-f025c03e-c1t3
node/gke-cluster-1-infra-pool-f025c03e-c1t3 uncordoned

kubectl uncordon gke-cluster-1-infra-pool-f025c03e-lbf4
node/gke-cluster-1-infra-pool-f025c03e-lbf4 uncordoned

kubectl get nodes
NAME                                       STATUS   ROLES    AGE   VERSION
gke-cluster-1-default-pool-77d8d79a-rltz   Ready    <none>   39h   v1.16.9-gke.2
gke-cluster-1-infra-pool-f025c03e-btq7     Ready    <none>   39h   v1.16.9-gke.2
gke-cluster-1-infra-pool-f025c03e-c1t3     Ready    <none>   39h   v1.16.9-gke.2
gke-cluster-1-infra-pool-f025c03e-lbf4     Ready    <none>   39h   v1.16.9-gke.2
```

Рассмотрим некоторое количество ключевых метрик, которые рекомендуется отслеживать при эксплуатации ElasticSearch:

- unassigned_shards - количество shard, для которых не нашлось подходящей ноды, их наличие сигнализирует о проблемах
- jvm_memory_usage - высокая загрузка (в процентах от выделенной памяти) может привести к замедлению работы кластера
- number_of_pending_tasks - количество задач, ожидающих выполнения. Значение метрики, отличное от нуля, может сигнализировать о наличии проблем внутри кластера

> Больше метрик с их описанием можно найти [здесь](https://habr.com/ru/company/yamoney/blog/358550/)

### EFK | nginx ingress

Для того, чтобы логи nginx-ingress отобразились в Kibana разрешим запуск fluent-bit на infra нодах в fluent-bit.values.yaml:

```yml
tolerations:
  - key: node-role
    operator: Equal
    value: infra
    effect: NoSchedule
```

```console
helm upgrade --install fluent-bit stable/fluent-bit --namespace observability -f fluent-bit.values.yaml
Release "fluent-bit" has been upgraded. Happy Helming!
NAME: fluent-bit
LAST DEPLOYED: Sat Jun  6 15:57:57 2020
NAMESPACE: observability
STATUS: deployed
REVISION: 4
NOTES:
fluent-bit is now running.
```

После появления логов nginx у нас возникнет следующая проблема:

```console
"_source": {
"log": "10.44.2.1 - - [11/Feb/2020:15:26:56 +0000] \"POST
/elasticsearch/kubernetes_cluster-*/_search?
rest_total_hits_as_int=true&ignore_unavailable=true&ignore_throttled=true&preference=158
1433758087&timeout=30000ms HTTP/1.1\" 499 0
\"http://kibana.35.184.239.20.xip.io/app/kibana\" \"Mozilla/5.0 (Macintosh; Intel Mac OS
X 10_15_2) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/80.0.3987.87 Safari/537.36\"
1535 0.303 [observability-kibana-kibana-5601] [] 10.44.0.70:5601 0 0.303 -
8de867470c348bd5598e554b5b36f8d9\n",
```

Сейчас лог представляет из себя строку, с которой сложно работать.

Мы можем использовать полнотекстовый поиск, но лишены возможности:

- Задействовать функции [KQL](https://www.elastic.co/guide/en/kibana/7.5/kuery-query.html)
- Полноценно проводить аналитику
- Создавать Dashboard по логам

Вспомним что у nginx есть возможность выбора формата и отформатируем лог в JSON

Отвечает за это ключ [log-format-escape-json](https://kubernetes.github.io/ingress-nginx/user-guide/nginx-configuration/configmap/#log-format-escape-json), добавим его в nginx-ingress.values.yaml

Также не забудем про опцию [log-format-upstream](https://kubernetes.github.io/ingress-nginx/user-guide/nginx-configuration/configmap/#log-format-escape-json)

nginx-ingress.values.yaml

```yml
  config:
    log-format-escape-json: "true"
    log-format-upstream: '{"remote_addr": "$proxy_protocol_addr", "x-forward-for": "$proxy_add_x_forwarded_for", "request_id": "$req_id", "remote_user": "$remote_user", "bytes_sent": $bytes_sent, "request_time": $request_time, "status":$status, "vhost": "$host", "request_proto": "$server_protocol", "path": "$uri", "request_query": "$args", "request_length": $request_length, "duration": $request_time,"method": "$request_method", "http_referrer": "$http_referer", "http_user_agent": "$http_user_agent" }'
```

```console
kubectl get  configmaps nginx-ingress-controller -n nginx-ingress -o yaml
apiVersion: v1
data:
  log-format-escape-json: "true"
kind: ConfigMap
metadata:
  annotations:
    meta.helm.sh/release-name: nginx-ingress
    meta.helm.sh/release-namespace: nginx-ingress
  creationTimestamp: "2020-06-06T13:11:23Z"
  labels:
    app: nginx-ingress
    app.kubernetes.io/managed-by: Helm
    chart: nginx-ingress-1.39.0
    component: controller
    heritage: Helm
    release: nginx-ingress
  name: nginx-ingress-controller
  namespace: nginx-ingress
  resourceVersion: "661825"
  selfLink: /api/v1/namespaces/nginx-ingress/configmaps/nginx-ingress-controller
  uid: ec1b4699-6af3-4814-8f8d-e21b906457df
```

Если все сделано корректно, формат логов должен измениться на следующий:

```console
"_source": {
  x-forward-for": "10.128.0.35",
  "request_id": "bfcee33afe75c099f7887d7e70b1ab00",
  "bytes_sent": 19087,
  "request_time": 1.168,
  "status": 200,
```

Теперь, когда мы научились собирать логи с nginx-ingress и смогли их структурировать, можно опробовать возможности Kibana для визуализации.

Перейдем на вкладку Visualize и создадим новую визуализацию с типом TSVB.

Для начала, создадим визуализацию, показывающую общее количество запросов к nginx-ingress. Для этого нам понадобится применить следующий KQL фильтр: kubernetes.labels.app : nginx-ingress

Добавим данный фильтр в Panel options нашей визуализации.

Также создадим визуализацию для отображения запросов к nginx-ingress со статусами:

- 200-299
- 300-399
- 400-499
- 500+

Пришло время объединить созданные нами визуализации в Dashboard.

- Создадим Dashboard (соответствующая вкладка в меню) и добавим на него наши визуализации.
- Экспортируем получившиеся визуализации и Dashboard и добавим файл export.ndjson в директорию kubernetes-logging

### Loki

Перейдем к еще одному решению для сбора и визуализации логов Kubernetes кластера

- Установим Loki в namespace observability, используя любой из [доступных способов](https://github.com/grafana/loki/blob/v1.3.0/docs/installation/README.md). Должны быть установлены непосредственно Loki и [Promtail](https://github.com/grafana/loki/tree/master/docs/clients/promtail)
- Модифицируем конфигурацию prometheus-operator таким образом, чтобы datasource Loki создавался сразу после установки оператора
- Итоговый файл prometheus-operator.values.yaml выложим в репозиторий в директорию kubernetes-logging
- Включим метрики для nginx-ingress

loki.values.yaml

```yml
promtail:
  tolerations:
  - key: node-role
    operator: Equal
    value: infra
    effect: NoSchedule
```

prometheus.values.yaml

```yml
  additionalDataSources:
    - name: Loki
      type: loki
      url: http://loki:3100/
      access: proxy
```

nginx-ingress.values.yaml

```yml
  metrics:
    enabled: true
    serviceMonitor:
      enabled: true
      namespace: observability
```

```console
helm repo add loki https://grafana.github.io/loki/charts
"loki" has been added to your repositories

helm repo update

helm upgrade --install loki loki/loki-stack -n observability -f  loki.values.yaml
Release "loki" does not exist. Installing it now.
NAME: loki
LAST DEPLOYED: Sat Jun  6 17:00:38 2020
NAMESPACE: observability
STATUS: deployed
REVISION: 1
NOTES:
The Loki stack has been deployed to your cluster. Loki can now be added as a datasource in Grafana.

See http://docs.grafana.org/features/datasources/loki/ for more detail.
```

В итоге должно получиться следующее:

```console
kubectl get pods -n observability
NAME                                                      READY   STATUS    RESTARTS   AGE
alertmanager-prometheus-operator-alertmanager-0           2/2     Running   0          3h3m
elasticsearch-exporter-65d6647f8b-9gw76                   1/1     Running   0          4h8m
elasticsearch-master-0                                    1/1     Running   0          4h56m
elasticsearch-master-1                                    1/1     Running   0          131m
elasticsearch-master-2                                    1/1     Running   0          125m
fluent-bit-8nl7n                                          1/1     Running   0          64m
fluent-bit-hb58v                                          1/1     Running   0          64m
fluent-bit-m2v2q                                          1/1     Running   0          64m
fluent-bit-t99hv                                          1/1     Running   0          64m
kibana-kibana-869dfc7ff-kvjl9                             1/1     Running   0          29h
loki-0                                                    1/1     Running   0          106s
loki-promtail-8m62g                                       1/1     Running   0          22s
loki-promtail-bpn8d                                       1/1     Running   0          22s
loki-promtail-dg2rl                                       1/1     Running   0          22s
loki-promtail-jw5xg                                       1/1     Running   0          22s
prometheus-operator-grafana-6567c8ff97-46hn8              2/2     Running   0          3h3m
prometheus-operator-kube-state-metrics-7f979567df-cwpzf   1/1     Running   0          3h3m
prometheus-operator-operator-874c49dfb-jqkbr              2/2     Running   0          164m
prometheus-operator-prometheus-node-exporter-7mjxz        1/1     Running   0          179m
prometheus-operator-prometheus-node-exporter-gmpfw        1/1     Running   0          179m
prometheus-operator-prometheus-node-exporter-r68t4        1/1     Running   0          179m
prometheus-operator-prometheus-node-exporter-w4ljx        1/1     Running   0          179m
prometheus-prometheus-operator-prometheus-0               3/3     Running   1          149m
```

### Loki | nginx ingress

До недавнего времени, единственным способом визуализации логов в Loki была функция Explore. Например, логи nginx-ingress с ее помощью можно отобразить следующим образом: {app="nginx-ingress"}

Loki, аналогично ElasticSearch умеет разбирать JSON лог по ключам, но, к сожалению, фильтрация по данным ключам на текущий момент не работает.

### Loki | Визуализация

Создадим Dashboard, на котором одновременно выведем метрики nginx-ingress и его логи

- Убедимся, что вместе с nginx-ingress устанавливается serviceMonitor, и Prometheus "видит" его (ответ выше в nginx-ingress.values.yaml)
- Создадим в Grafana новый Dashboard
- Добавим для него следующие [переменные](https://grafana.com/docs/grafana/latest/reference/templating/) (взяты из [официального Dashoboard](https://github.com/kubernetes/ingress-nginx/blob/master/deploy/grafana/dashboards/nginx.json) для nginx-ingress):

- namespace
- controller_class
- controller
- ingress

- Создадим новую панель и добим туда следующую [query] (взято из [официального Dashboard](https://github.com/kubernetes/ingress-nginx/blob/master/deploy/grafana/dashboards/nginx.json) для nginx-ingress):

```console
sum(rate(nginx_ingress_controller_requests{controller_pod=~"$controller",controller_class=~"$controller_class",namespace=~"$namespace",ingress=~"$ingress", status!~"[4-5].*"} [1m])) by (ingress) /
sum(rate(nginx_ingress_controller_requests{controller_pod=~"$controller",controller_class=~"$controller_class",namespace=~"$namespace",ingress=~"$ingress"}[1m])) by (ingress)
```

- Аналогичным образом добавим панель, позволяющую оценить количество запросов к nginx-ingress в секунду
- Добавим панель с логами и укажем для нее следующие настройки Query: {app="nginx-ingress"}
- Выгрузим из Grafana JSON с финальным Dashboard и поместим его в файл kubernetes-logging/nginx-ingress.json

### Event logging | k8s-event-logger

Также можно обратить внимание на еще одну небольшую, но очень полезную [утилиту](https://github.com/max-rocket-internet/k8s-event-logger), позволяющую получить и сохранить event'ы Kubernetes в выбранном решении для логирования

Например, event, говорящий нам о том, что liveness probe у prometheus-operator выполнилась неуспешно

Развернем:

```console
helm upgrade --install k8s-event-logger k8s-event-logger -n observability --create-namespace  
Release "k8s-event-logger" does not exist. Installing it now.
NAME: k8s-event-logger
LAST DEPLOYED: Sun Jun  7 22:19:18 2020
NAMESPACE: observability
STATUS: deployed
REVISION: 1
TEST SUITE: None
NOTES:
To verify that the k8s-event-logger pod has started, run:

  kubectl --namespace=observability get pods -l "app.kubernetes.io/name=k8s-event-logger,app.kubernetes.io/instance=k8s-event-logger"

kubectl get pods -n observability
NAME                                READY   STATUS    RESTARTS   AGE
k8s-event-logger-6db47fdcfd-s26z4   1/1     Running   0          2m35s
```

### Audit logging | Задание со ⭐

Еще один важный тип логов, который рекомендуется собирать и хранить - логи [аудита](https://kubernetes.io/docs/tasks/debug-application-cluster/audit/)

Получить их в GKE сложнее, чем в self-hosted кластерах из-за того, что доступ к master нодам, на которых запущен kubeapiserver, отсутствует.  
Поэтому развернем self-hosted кластер и настроим сбор [аудит](https://kubernetes.io/docs/tasks/debug-application-cluster/audit/) логов:

Наши ноды:

```console
kubectl get nodes
NAME      STATUS   ROLES    AGE     VERSION
master1   Ready    master   2d23h   v1.18.3
master2   Ready    master   2d20h   v1.18.3
worker1   Ready    <none>   2d20h   v1.18.3
worker2   Ready    <none>   2d20h   v1.18.3
worker3   Ready    <none>   2d20h   v1.18.3
```

- Развернем Elasticsearch и Kibana
- Создадим fluent-bit.audit.values.yaml:
  - Запускающий Fluent-bit на всех нодах
  - Включим опцию аудита в параметрах
- Развернем Fluent-bit

```yml
backend:
  type: es
  es:
    host: elasticsearch-master

audit:
  enable: true
  input:
    memBufLimit: 35MB
    parser: docker
    tag: audit.*
    path: /var/log/kube-audit/audit.log
    bufferChunkSize: 2MB
    bufferMaxSize: 10MB
    skipLongLines: On
    key: kubernetes-audit

rawConfig: |
  @INCLUDE fluent-bit-service.conf
  @INCLUDE fluent-bit-input.conf
  @INCLUDE fluent-bit-filter.conf
  @INCLUDE fluent-bit-output.conf

tolerations:
  - operator: Exists
```

- Создадим необходимые для работы директории

```console
sudo mkdir -p /etc/kubernetes/policies
sudo mkdir -p /var/log/kube-audit
```

Создадим /etc/kubernetes/policies/audit-policy.yaml со следующим содержимым:

```yml
apiVersion: audit.k8s.io/v1
kind: Policy
rules:
  - level: Metadata
```

> Используем простейшую политику аудита - Metadata - логирование метаданных запроса: пользователя, время запроса, целевой ресурс (pod, namespace и т.п.), тип действия (verb)

Добавим в /etc/kubernetes/manifests/kube-apiserver.yaml

- Включим аудит, нам нужно передать контейнеру в api-server три обязательных параметра:

```yml
- --audit-policy-file=/etc/kubernetes/policies/audit-policy.yaml
- --audit-log-path=/var/log/kube-audit/audit.log
- --audit-log-format=json
```

- audit-policy-file — путь до YAML-файла с описанием политики (policy) аудита:

```yml
  volumeMounts:
    - mountPath: /etc/kubernetes/policies
      name: policies
      readOnly: true
  volumes:
  - hostPath:
      path: /etc/kubernetes/policies
      type: DirectoryOrCreate
    name: policies
```

- audit-log-path — путь до файла лога:

```yml
  volumeMounts:
    - mountPath: /var/log/kube-audit
      name: logs
      readOnly: false
  volumes:
  - hostPath:
      path: /var/log/kube-audit
      type: DirectoryOrCreate
    name: logs
```

Перезапустим api-server:

```console
sudo docker stop $(sudo docker ps | grep k8s_kube-apiserver | awk '{print $1}')
```

Теперь перейдем в Kibana, где мы сможем наблюдать следующие логи аудита:

```console
_source:
kind:Event @timestamp:Jun 8, 2020 @ 01:12:18.763 apiVersion:audit.k8s.io/v1 level:Metadata auditID:83490317-c0c2-4a30-9726-77ca7b37c47b stage:RequestReceived requestURI:/apis/coordination.k8s.io/v1/namespaces/kube-system/leases/kube-scheduler?timeout=10s verb:update user.username:system:kube-scheduler user.groups:system:authenticated sourceIPs:10.2.1.2 userAgent:kube-scheduler/v1.18.3 (linux/amd64) kubernetes/2e7996e/leader-election objectRef.resource:leases objectRef.namespace:kube-system objectRef.name:kube-
```

### Host logging | Задание со ⭐

- На текущий момент мы лишены возможности централизованного просмотра логов с виртуальных машин, на которых запущен Kubernetes
- Модернизируем конфигурацию fluent-bit таким образом, чтобы данные логи отображались в ElasticSearch

Добавим в наш fluent-bit.audit.values.yaml:

```yml
  [INPUT]
      Name         Tail
      Path         /var/log/syslog
      Path_Key     log_file
      DB           /run/fluent-bit-messages.state
      Parser       syslog-rfc3164
  [INPUT]
      Name         Tail
      Path         /var/log/kern.log
      Path_Key     log_file
      DB           /run/fluent-bit-kern.state
      Parser       syslog-rfc3164

  [INPUT]
      Name         Tail
      Path         /var/log/auth.log
      Path_Key     log_file
      DB           /run/fluent-bit-auth.state
      Parser       syslog-rfc3164

  [INPUT]
      Name         Tail
      Path         /var/log/docker.log
      Path_Key     log_file
      DB           /run/fluent-bit-docker.state
      Parser       docker-daemon
```

Применим и сможем наблюдать в Kibana логи с хостов (к примеру syslog)

```console
_source:
log_file:/var/log/syslog @timestamp:Jun 8, 2020 @ 15:13:32.648 log:Jun 8 13:13:32 master2 kubelet[1111]: E0608 13:13:32.646400 1111 file.go:187] Can't process manifest file "/etc/kubernetes/manifests/kube-apiserver.yaml": invalid pod: [spec.containers[0].volumeMounts[5].mountPath: Invalid value: "/usr/share/ca-certificates": must be unique] _id:8doQlHIBJSoEJCXikBpI _type:flb_type _index:kubernetes_cluster-2020.06.08 _score: -
```

## Мониторинг сервиса в кластере k8s

### Prometheus-operator

Развертывать prometheus-operator будет через Helm3:

```console
kubectl create ns monitoring
helm upgrade --install  prometheus-operator stable/prometheus-operator -n monitoring
```

Проверяем:

```console

kubectl get pods -n monitoring
NAME                                                     READY   STATUS    RESTARTS   AGE
alertmanager-prometheus-operator-alertmanager-0          2/2     Running   0          82s
prometheus-operator-grafana-64bcbf975f-7dx9k             2/2     Running   0          88s
prometheus-operator-kube-state-metrics-5fdcd78bc-gnqv4   1/1     Running   0          88s
prometheus-operator-operator-778d5d7b98-6c6pj            2/2     Running   0          88s
prometheus-operator-prometheus-node-exporter-9grbk       1/1     Running   0          88s
prometheus-prometheus-operator-prometheus-0              3/3     Running   1          72s
```

### nginx (kubernetes-monitoring/nginx)

Подготовим манифесты для:

- Deployment с nginx и sidecar [nginx-exporter](https://github.com/nginxinc/nginx-prometheus-exporter) контейнерами со следующими характеристиками
  - nginx работающий на 80 порту с поддержкой [nginx-статуса](http://nginx.org/ru/docs/http/ngx_http_stub_status_module.html) доступного на порту 8080 по адресу <http://127.0.0.1:8080/basic_status>
  - nginx-exporter отдающий метрики в формате prometheus на порту 9113
  - три реплики
- ConfigMap с конфигурацией nginx
- Service для доступа к нашим pods по необходимым портам
- CR ServiceMonitor для мониторинга наших сервисов

nginx-configMap.yaml

```yml
apiVersion: v1
kind: ConfigMap
metadata:
  name: nginx-config
data:
  nginx.conf: |
    user  nginx;
    worker_processes  1;

    error_log  /var/log/nginx/error.log warn;
    pid        /var/run/nginx.pid;


    events {
        worker_connections  1024;
    }


    http {
        include       /etc/nginx/mime.types;
        default_type  application/octet-stream;

        log_format  main  '$remote_addr - $remote_user [$time_local] "$request" '
                          '$status $body_bytes_sent "$http_referer" '
                          '"$http_user_agent" "$http_x_forwarded_for"';

        access_log  /var/log/nginx/access.log  main;

        sendfile        on;

        keepalive_timeout  65;

        server {
            listen       80;
            server_name  localhost;

            location / {
                root   /usr/share/nginx/html;
                index  index.html index.htm;
            }

            error_page   500 502 503 504  /50x.html;
            location = /50x.html {
                root   /usr/share/nginx/html;
            }
        }
        server {
            listen       8080;
            server_name  localhost;

            location = /basic_status {
                stub_status;
                allow 127.0.0.1;
                deny all;
            }
        }
    }
```

nginx-deployment.yaml

```yml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx
  labels:
    app: nginx  
spec:
  replicas: 3
  selector:
    matchLabels:
      app: nginx
  template:
    metadata:
      labels:
        app: nginx
    spec:
      containers:
      - name: nginx
        image: nginx:1.19.0-alpine
        ports:
        - containerPort: 80
        volumeMounts:
          - name: nginx-config
            mountPath: /etc/nginx/nginx.conf
            subPath: nginx.conf
      - name: nginx-exporter
        image: nginx/nginx-prometheus-exporter:0.7.0
        env:
          - name: SCRAPE_URI
            value: "http://127.0.0.1:8080/basic_status"
          - name: NGINX_RETRIES
            value: "10"
        ports:
        - containerPort: 9113
      volumes:
        - name: nginx-config
          configMap:
            name: nginx-config
```

nginx-nginx-service.yaml

```yml
apiVersion: v1
kind: Service
metadata:
  name: nginx
  labels:
    app: nginx
spec:
  selector:
    app: nginx
  type: ClusterIP
  ports:
  - name: http
    port: 80
    protocol: TCP
    targetPort: 80
  - name: nginx-exporter
    port: 9113
    protocol: TCP
    targetPort: 9113
```

nginx-serviceMonitor.yaml

```yml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: nginx-sm
  namespace: default
  labels:
    release: prometheus-operator
spec:
  namespaceSelector:
    matchNames:
    - default
  selector:
    matchLabels:
      app: nginx
  endpoints:
  - port: nginx-exporter
```

Развернем:

```console
kubectl apply -f nginx-configMap.yaml
kubectl apply -f nginx-deployment.yaml
kubectl apply -f nginx-nginx-service.yaml
kubectl apply -f nginx-serviceMonitor.yaml
```

И проверим работу nginx-exporter:

```console
kubectl get pods
NAME                     READY   STATUS    RESTARTS   AGE
nginx-869f7cf565-hk2xd   2/2     Running   0          11h
nginx-869f7cf565-kjdk8   2/2     Running   0          11h
nginx-869f7cf565-qd7wx   2/2     Running   0          11h

kubectl port-forward service/nginx 9113:9113

curl http://127.0.0.1:9113/metrics
# HELP nginx_connections_accepted Accepted client connections
# TYPE nginx_connections_accepted counter
nginx_connections_accepted 1024
# HELP nginx_connections_active Active client connections
# TYPE nginx_connections_active gauge
nginx_connections_active 1
# HELP nginx_connections_handled Handled client connections
# TYPE nginx_connections_handled counter
nginx_connections_handled 1024
# HELP nginx_connections_reading Connections where NGINX is reading the request header
# TYPE nginx_connections_reading gauge
nginx_connections_reading 0
# HELP nginx_connections_waiting Idle client connections
# TYPE nginx_connections_waiting gauge
nginx_connections_waiting 0
# HELP nginx_connections_writing Connections where NGINX is writing the response back to the client
# TYPE nginx_connections_writing gauge
nginx_connections_writing 1
# HELP nginx_http_requests_total Total http requests
# TYPE nginx_http_requests_total counter
nginx_http_requests_total 3355
# HELP nginx_up Status of the last metric scrape
# TYPE nginx_up gauge
nginx_up 1
# HELP nginxexporter_build_info Exporter build information
# TYPE nginxexporter_build_info gauge
nginxexporter_build_info{gitCommit="a2910f1",version="0.7.0"} 1
```

### Prometheus UI

Выполним:

```console
kubectl port-forward service/prometheus-operator-prometheus -n monitoring 9090:9090
```

Далее заходим по адресу <http://127.0.0.1:9090/targets> и наблюдаем наши endpoints в default/nginx-sm в количестве трех реплик.

### Grafana UI

Выполним:

```console
kubectl port-forward service/prometheus-operator-grafana  -n monitoring 8000:80
```

Далее зайдем в Grafana по адресу <http://127.0.0.1:8000/> используя логин/пароль admin/prom-operator и импортируем [dashboard](https://github.com/nginxinc/nginx-prometheus-exporter/tree/master/grafana).

Теперь мы можем наблюдать статусы наших nginx и необходимые нам метрики:

![Grafana](kubernetes-monitoring/grafana.png)

## Операторы, CustomResourceDefinition

### Подготовка minikube

❗ minikube addons disable default-storageclass  
❗ pip install kopf jinja2 kubernetes

### Что сделаем

- В ходе работы мы:
  - Напишем CustomResource и CustomResourceDefinition для mysql оператора
  - 🐍 Напишем часть логики mysql оператора при помощи python KOPF
- Сделаем соберем образ и сделаем деплой оператора.

### Что должно быть в описании MySQL

Для создания pod с MySQL оператору понадобится знать:

- Какой образ с MySQL использовать
- Какую db создать
- Какой пароль задать для доступа к MySQL

То есть мы бы хотели, чтобы описание MySQL выглядело примерно так:

```yml
apiVersion: otus.homework/v1
kind: MySQL
metadata:
  name: mysql-instance
spec:
  image: mysql:5.7
  database: otus-database
  password: otuspassword  # Так делать не нужно, следует использовать secret
  storage_size: 1Gi
```

### CustomResource

Cоздадим CustomResource deploy/cr.yml со следующим содержимым:

```yml
apiVersion: otus.homework/v1
kind: MySQL
metadata:
  name: mysql-instance
spec:
  image: mysql:5.7
  database: otus-database
  password: otuspassword  # Так делать не нужно, следует использовать secret
  storage_size: 1Gi
usless_data: "useless info"
```

Пробуем применить его:

```console
kubectl apply -f deploy/cr.yml
error: unable to recognize "deploy/cr.yml": no matches for kind "MySQL" in version "otus.homework/v1"
```

Ошибка связана с отсутсвием объектов типа MySQL в API kubernetes. Исправим это недоразумение.

### CustomResourceDefinition

CustomResourceDefinition - это ресурс для определения других ресурсов (далее CRD)

Создадим CRD deploy/crd.yml:

```yml
apiVersion: apiextensions.k8s.io/v1beta1
kind: CustomResourceDefinition
metadata:
  name: mysqls.otus.homework # name состоит из <plural>.<group>
spec:
  scope: Namespaced     # Длибо Namespaced, либо Cluster
  group: otus.homework  # REST API: /apis/<group>/<version>
  versions:             # Список версий
    - name: v1
      served: true      # каждую версию можно включать и выключать
      storage: true     # но только одну можно хранить
  names:                # различные форматы имени объекта CR
    kind: MySQL         # CamelCased в единственном числе
    plural: mysqls      # URL: /apis/<group>/<version>/<plural>
    singular: mysql     # для командной строки
    shortNames:
      - ms              # сокращенная версия для командной строки
    preserveUnknownFields: false
```

### Создаем CRD и CR

Создадим CRD:

```console
kubectl apply -f deploy/crd.yml
customresourcedefinition.apiextensions.k8s.io/mysqls.otus.homework created
```

Cоздаем CR:

```console
kubectl apply -f deploy/cr.yml
mysql.otus.homework/mysql-instance created
```

### Взаимодействие с объектами CR CRD

C созданными объектами можно взаимодействовать через kubectl:

```console
kubectl get crd
NAME                   CREATED AT
mysqls.otus.homework   2020-06-01T16:16:05Z
```

```console
kubectl get mysqls.otus.homework
NAME             AGE
mysql-instance   44s
```

```console
kubectl describe mysqls.otus.homework mysql-instance
Name:         mysql-instance
Namespace:    default
Labels:       <none>
Annotations:  kubectl.kubernetes.io/last-applied-configuration:
                {"apiVersion":"otus.homework/v1","kind":"MySQL","metadata":{"annotations":{},"name":"mysql-instance","namespace":"default"},"spec":{"datab...
API Version:  otus.homework/v1
Kind:         MySQL
Metadata:
  Creation Timestamp:  2020-06-01T16:16:20Z
  Generation:          1
  Managed Fields:
    API Version:  otus.homework/v1
    Fields Type:  FieldsV1
    fieldsV1:
      f:metadata:
        f:annotations:
          .:
          f:kubectl.kubernetes.io/last-applied-configuration:
      f:spec:
        .:
        f:database:
        f:image:
        f:password:
        f:storage_size:
      f:usless_data:
    Manager:         kubectl
    Operation:       Update
    Time:            2020-06-01T16:16:20Z
  Resource Version:  539535
  Self Link:         /apis/otus.homework/v1/namespaces/default/mysqls/mysql-instance
  UID:               564e0916-7192-4e4c-8a98-755387dfe410
Spec:
  Database:      otus-database
  Image:         mysql:5.7
  Password:      otuspassword
  storage_size:  1Gi
usless_data:     useless info
Events:          <none>
```

### Validation

На данный момент мы никак не описали схему нашего CustomResource. Объекты типа mysql могут иметь абсолютно произвольные поля, нам бы хотелось этого избежать, для этого будем использовать validation. Для начала удалим CR mysql-instance:

```console
kubectl delete mysqls.otus.homework mysql-instance
mysql.otus.homework "mysql-instance" deleted
```

Добавим в спецификацию CRD ( spec ) параметры validation:

```yml
  validation:
    openAPIV3Schema:
      type: object
      properties:
        apiVersion:
          type: string # Тип данных поля ApiVersion
        kind:
          type: string # Тип данных поля kind
        metadata:
          type: object # Тип поля metadata
          properties:  # Доступные параметры и их тип данных поля metadata (словарь)
            name:
              type: string
        spec:
          type: object
          properties:
            image:
              type: string
            database:
              type: string
            password:
              type: string
            storage_size:
              type: string
```

Пробуем применить CRD и CR:

```console
kubectl apply -f deploy/crd.yml
customresourcedefinition.apiextensions.k8s.io/mysqls.otus.homework configured

kubectl apply -f deploy/cr.yml
error: error validating "deploy/cr.yml": error validating data: ValidationError(MySQL): unknown field "usless_data" in homework.otus.v1.MySQL; if you choose to ignore these errors, turn validation off with --validate=false
```

Убираем из cr.yml: usless_data: "useless info"

Применяем:

```console
kubectl apply -f deploy/cr.yml
mysql.otus.homework/mysql-instance created
```

Ошибки больше нет

### Задание по CRD

Если сейчас из описания mysql убрать строчку из спецификации, то манифест будет принят API сервером. Для того, чтобы этого избежать, добавим описание обязательный полей в CustomResourceDefinition:

```yml
required: ["spec"]
required: ["image", "database", "password", "storage_size"]
```

```console
kubectl apply -f deploy/crd.yml
customresourcedefinition.apiextensions.k8s.io/mysqls.otus.homework configured
```

```console
kubectl apply -f deploy/cr.yml
mysql.otus.homework/mysql-instance created
```

Если удалить из cr.yml поле storage_size, то получим следующую ошибку:

```console
kubectl apply -f deploy/cr.yml
error: error validating "deploy/cr.yml": error validating data: ValidationError(MySQL.spec): missing required field "storage_size" in homework.otus.v1.MySQL.spec; if you choose to ignore these errors, turn validation off with --validate=false
```

### Операторы

- Оператор включает в себя CustomResourceDefinition и сustom сontroller
  - CRD содержит описание объектов CR
  - Контроллер следит за объектами определенного типа, и осуществляет всю логику работы оператора
- CRD мы уже создали далее будем писать свой контроллер (все задания по написанию контроллера дополнительными)
- Далее развернем custom controller

### Описание контроллера

Используемый/написанный нами контроллер будет обрабатывать два типа событий:

- При создании объекта типа ( kind: mySQL ), он будет:
  - Cоздавать PersistentVolume, PersistentVolumeClaim, Deployment, Service для mysql
  - Создавать PersistentVolume, PersistentVolumeClaim для бэкапов базы данных, если их еще нет.
  - Пытаться восстановиться из бэкапа
- При удалении объекта типа ( kind: mySQL ), он будет:
  - Удалять все успешно завершенные backup-job и restore-job
  - Удалять PersistentVolume, PersistentVolumeClaim, Deployment, Service для mysql

### MySQL контроллер

Создадим файл mysqloperator.py. Для написания контроллера будем использовать kopf.

```py
# Добавим импорт необходимых библиотек:
import kopf
import yaml
import kubernetes
import time
from jinja2 import Environment, FileSystemLoader
```

В дирректории kubernetes-operators/build/templates создадим шаблоны:

- mysql-deployment.yml.j2
- mysql-service.yml.j2
- mysql-pv.yml.j2
- mysql-pvc.yml.j2
- backup-pv.yml.j2
- backup-pvc.yml.j2
- backup-job.yml.j2
- restore-job.yml.j2

```py
#Добавим функцию, для обработки Jinja шаблонов и преобразования YAML в JSON:
def render_template(filename, vars_dict):
    env = Environment(loader=FileSystemLoader('./templates'))
    template = env.get_template(filename)
    yaml_manifest = template.render(vars_dict)
    json_manifest = yaml.load(yaml_manifest)
    return json_manifest
```

Ниже добавим декоратор:

Функция mysql_on_create будет запускаться при создании объектов типа MySQL.

```py
@kopf.on.create('otus.homework', 'v1', 'mysqls')
# Функция, которая будет запускаться при создании объектов тип MySQL:
def mysql_on_create(body, spec, **kwargs):
    name = body['metadata']['name']
    image = body['spec']['image']
    password = body['spec']['password']
    database = body['spec']['database']
    storage_size = body['spec']['storage_size']
```

Добавим в декоратор рендер шаблонов:

```py
    # Генерируем JSON манифесты для деплоя
    persistent_volume = render_template('mysql-pv.yml.j2',
                                        {'name': name,
                                         'storage_size': storage_size})
    persistent_volume_claim = render_template('mysql-pvc.yml.j2',
                                              {'name': name,
                                               'storage_size': storage_size})
    service = render_template('mysql-service.yml.j2', {'name': name})

    deployment = render_template('mysql-deployment.yml.j2', {
        'name': name,
        'image': image,
        'password': password,
        'database': database})
```

Для создания объектов пользуемся библиотекой kubernetes:

```py
    api = kubernetes.client.CoreV1Api()
    # Создаем mysql PV:
    api.create_persistent_volume(persistent_volume)
    # Создаем mysql PVC:
    api.create_namespaced_persistent_volume_claim('default', persistent_volume_claim)
    # Создаем mysql SVC:
    api.create_namespaced_service('default', service)

    # Создаем mysql Deployment:
    api = kubernetes.client.AppsV1Api()
    api.create_namespaced_deployment('default', deployment)
```

Сейчас должно получиться, что-то похожее на:

```py
import kopf
import yaml
import kubernetes
import time
from jinja2 import Environment, FileSystemLoader


def render_template(filename, vars_dict):
    env = Environment(loader=FileSystemLoader('./templates'))
    template = env.get_template(filename)
    yaml_manifest = template.render(vars_dict)
    json_manifest = yaml.load(yaml_manifest)
    return json_manifest


@kopf.on.create('otus.homework', 'v1', 'mysqls')
# Функция, которая будет запускаться при создании объектов тип MySQL:
def mysql_on_create(body, spec, **kwargs):
    name = body['metadata']['name']
    image = body['spec']['image']
    password = body['spec']['password']
    database = body['spec']['database']
    storage_size = body['spec']['storage_size']

    # Генерируем JSON манифесты для деплоя
    persistent_volume = render_template('mysql-pv.yml.j2',
                                        {'name': name,
                                         'storage_size': storage_size})
    persistent_volume_claim = render_template('mysql-pvc.yml.j2',
                                              {'name': name,
                                               'storage_size': storage_size})
    service = render_template('mysql-service.yml.j2', {'name': name})

    deployment = render_template('mysql-deployment.yml.j2', {
        'name': name,
        'image': image,
        'password': password,
        'database': database})

    api = kubernetes.client.CoreV1Api()
    # Создаем mysql PV:
    api.create_persistent_volume(persistent_volume)
    # Создаем mysql PVC:
    api.create_namespaced_persistent_volume_claim('default', persistent_volume_claim)
    # Создаем mysql SVC:
    api.create_namespaced_service('default', service)

    # Создаем mysql Deployment:
    api = kubernetes.client.AppsV1Api()
    api.create_namespaced_deployment('default', deployment)
```

С такой конфигурацие уже должны обрабатываться события при создании cr.yml, проверим, для этого из папки build.

Если cr.yml был до этого применен, то увидим:

```console
kopf run mysql-operator.py
[2020-06-02 00:04:35,625] kopf.objects         [INFO    ] [default/mysql-instance] Handler 'mysql_on_create' succeeded.
[2020-06-02 00:04:35,625] kopf.objects         [INFO    ] [default/mysql-instance] All handlers succeeded for creation.
```

> Объект создался до того, как запустили контролле потому что реализован level triggered механизм - опрос изменений во времени.

Если сделать kubectl delete mysqls.otus.homework mysqlinstance , то CustomResource будет удален, но наш контроллер ничего не
сделает т. к обработки событий на удаление у нас нет.

Удалим все ресурсы, созданные контроллером:

```console
kubectl delete mysqls.otus.homework mysql-instance
kubectl delete deployments.apps mysql-instance
kubectl delete pvc mysql-instance-pvc
kubectl delete pv mysql-instance-pv
kubectl delete svc mysql-instance
mysql.otus.homework "mysql-instance" deleted
deployment.apps "mysql-instance" deleted
persistentvolumeclaim "mysql-instance-pvc" deleted
persistentvolume "mysql-instance-pv" deleted
service "mysql-instance" deleted
```

Для того, чтобы обработать событие удаления ресурса используется другой декоратор, в нем можно описать удаление ресурсов, аналогично тому, как мы их создавали, но есть более удобный метод.

Для удаления ресурсов, сделаем deployment,svc,pv,pvc дочерними ресурсами к mysql, для этого в тело функции mysql_on_create , после генерации json манифестов добавим:

```py
    # Определяем, что созданные ресурсы являются дочерними к управляемому CustomResource:
    kopf.append_owner_reference(persistent_volume, owner=body)
    kopf.append_owner_reference(persistent_volume_claim, owner=body)  # addopt
    kopf.append_owner_reference(service, owner=body)
    kopf.append_owner_reference(deployment, owner=body)
    # ^ Таким образом при удалении CR удалятся все, связанные с ним pv,pvc,svc, deployments
```

В конец файла добавим обработку события удаления ресурса mysql:

```py
# Добавим обработку события удаления ресурса mysql:
@kopf.on.delete('otus.homework', 'v1', 'mysqls')
def delete_object_make_backup(body, **kwargs):
    return {'message': "mysql and its children resources deleted"}
```

Перезапустим контроллер, создадим и удалим mysql-instance, проверим, что все pv, pvc, svc и deployments удалились.

```console
kubectl apply -f cr.yml
mysql.otus.homework/mysql-instance created

kopf run mysql-operator.py
[2020-06-02 00:20:00,980] kopf.objects         [INFO    ] [default/mysql-instance] Handler 'mysql_on_create' succeeded.
[2020-06-02 00:20:00,981] kopf.objects         [INFO    ] [default/mysql-instance] All handlers succeeded for creation.
```

```console
kubectl delete -f cr.yml
mysql.otus.homework "mysql-instance" deleted

kopf run mysql-operator.py
[2020-06-02 00:21:47,967] kopf.objects         [INFO    ] [default/mysql-instance] Handler 'delete_object_make_backup' succeeded.
[2020-06-02 00:21:47,968] kopf.objects         [INFO    ] [default/mysql-instance] All handlers succeeded for deletion.
```

```cosnsole
kubectl get deployments
No resources found in default namespace.

kubectl get pv
No resources found in default namespace.

kubectl get pvc
No resources found in default namespace.
```

Теперь добавим создание pv, pvc для backup и restore job. Для этого после создания deployment добавим следующий код:

```py
    # Cоздаем PVC  и PV для бэкапов:
    try:
        backup_pv = render_template('backup-pv.yml.j2', {'name': name})
        api = kubernetes.client.CoreV1Api()
        print(api.create_persistent_volume(backup_pv))
        api.create_persistent_volume(backup_pv)
    except kubernetes.client.rest.ApiException:
        pass

    try:
        backup_pvc = render_template('backup-pvc.yml.j2', {'name': name})
        api = kubernetes.client.CoreV1Api()
        api.create_namespaced_persistent_volume_claim('default', backup_pvc)
    except kubernetes.client.rest.ApiException:
        pass
```

Конструкция try, except - это обработка исключений, в данном случае, нужна, чтобы наш контроллер не пытался бесконечно пересоздать pv и pvc для бэкапов, т к их жизненный цикл отличен от жизненного цикла mysql.

Далее нам необходимо реализовать создание бэкапов и восстановление из них. Для этого будут использоваться Job. Поскольку при запуске Job, повторно ее запустить нельзя, нам нужно реализовать логику удаления успешно законченных jobs c определенным именем.

Для этого выше всех обработчиков событий (под функций render_template) добавим следующую функцию:

```py
def delete_success_jobs(mysql_instance_name):
    print("start deletion")
    api = kubernetes.client.BatchV1Api()
    jobs = api.list_namespaced_job('default')
    for job in jobs.items:
        jobname = job.metadata.name
        if (jobname == f"backup-{mysql_instance_name}-job") or \
                (jobname == f"restore-{mysql_instance_name}-job"):
            if job.status.succeeded == 1:
                api.delete_namespaced_job(jobname,
                                          'default',
                                          propagation_policy='Background')
```

Также нам понадобится функция, для ожидания пока наша backup job завершится, чтобы дождаться пока backup выполнится перед удалением mysql deployment, svc, pv, pvc.  
Опишем ее:

```py
def wait_until_job_end(jobname):
    api = kubernetes.client.BatchV1Api()
    job_finished = False
    jobs = api.list_namespaced_job('default')
    while (not job_finished) and \
            any(job.metadata.name == jobname for job in jobs.items):
        time.sleep(1)
        jobs = api.list_namespaced_job('default')
        for job in jobs.items:
            if job.metadata.name == jobname:
                print(f"job with { jobname }  found,wait untill end")
                if job.status.succeeded == 1:
                    print(f"job with { jobname }  success")
                    job_finished = True
```

Добавим запуск backup-job и удаление выполненных jobs в функцию delete_object_make_backup:

```py
    name = body['metadata']['name']
    image = body['spec']['image']
    password = body['spec']['password']
    database = body['spec']['database']

    delete_success_jobs(name)

    # Cоздаем backup job:
    api = kubernetes.client.BatchV1Api()
    backup_job = render_template('backup-job.yml.j2', {
        'name': name,
        'image': image,
        'password': password,
        'database': database})
    api.create_namespaced_job('default', backup_job)
    wait_until_job_end(f"backup-{name}-job")
```

Добавим генерацию json из шаблона для restore-job:

```py
    restore_job = render_template('restore-job.yml.j2', {
        'name': name,
        'image': image,
        'password': password,
        'database': database})
```

Добавим попытку восстановиться из бэкапов после deployment mysql:

```py
    try:
        api = kubernetes.client.BatchV1Api()
        api.create_namespaced_job('default', restore_job)
    except kubernetes.client.rest.ApiException:
        pass
```

Добавим зависимость restore-job от объектов mysql (возле других owner_reference):

```py
    kopf.append_owner_reference(restore_job, owner=body)
```

Теперь должно выглядеть так:

```py
import kopf
import yaml
import kubernetes
import time
from jinja2 import Environment, FileSystemLoader


def wait_until_job_end(jobname):
    api = kubernetes.client.BatchV1Api()
    job_finished = False
    jobs = api.list_namespaced_job('default')
    while (not job_finished) and \
            any(job.metadata.name == jobname for job in jobs.items):
        time.sleep(1)
        jobs = api.list_namespaced_job('default')
        for job in jobs.items:
            if job.metadata.name == jobname:
                print(f"job with { jobname }  found,wait untill end")
                if job.status.succeeded == 1:
                    print(f"job with { jobname }  success")
                    job_finished = True


def render_template(filename, vars_dict):
    env = Environment(loader=FileSystemLoader('./templates'))
    template = env.get_template(filename)
    yaml_manifest = template.render(vars_dict)
    json_manifest = yaml.load(yaml_manifest)
    return json_manifest


def delete_success_jobs(mysql_instance_name):
    print("start deletion")
    api = kubernetes.client.BatchV1Api()
    jobs = api.list_namespaced_job('default')
    for job in jobs.items:
        jobname = job.metadata.name
        if (jobname == f"backup-{mysql_instance_name}-job") or \
                (jobname == f"restore-{mysql_instance_name}-job"):
            if job.status.succeeded == 1:
                api.delete_namespaced_job(jobname,
                                          'default',
                                          propagation_policy='Background')


@kopf.on.create('otus.homework', 'v1', 'mysqls')
# Функция, которая будет запускаться при создании объектов тип MySQL:
def mysql_on_create(body, spec, **kwargs):
    name = body['metadata']['name']
    image = body['spec']['image']
    password = body['spec']['password']
    database = body['spec']['database']
    storage_size = body['spec']['storage_size']

    # Генерируем JSON манифесты для деплоя
    persistent_volume = render_template('mysql-pv.yml.j2',
                                        {'name': name,
                                         'storage_size': storage_size})
    persistent_volume_claim = render_template('mysql-pvc.yml.j2',
                                              {'name': name,
                                               'storage_size': storage_size})
    service = render_template('mysql-service.yml.j2', {'name': name})

    deployment = render_template('mysql-deployment.yml.j2', {
        'name': name,
        'image': image,
        'password': password,
        'database': database})
    restore_job = render_template('restore-job.yml.j2', {
        'name': name,
        'image': image,
        'password': password,
        'database': database})

    # Определяем, что созданные ресурсы являются дочерними к управляемому CustomResource:
    kopf.append_owner_reference(persistent_volume, owner=body)
    kopf.append_owner_reference(persistent_volume_claim, owner=body)  # addopt
    kopf.append_owner_reference(service, owner=body)
    kopf.append_owner_reference(deployment, owner=body)
    kopf.append_owner_reference(restore_job, owner=body)

    # ^ Таким образом при удалении CR удалятся все, связанные с ним pv,pvc,svc, deployments

    api = kubernetes.client.CoreV1Api()
    # Создаем mysql PV:
    api.create_persistent_volume(persistent_volume)
    # Создаем mysql PVC:
    api.create_namespaced_persistent_volume_claim('default', persistent_volume_claim)
    # Создаем mysql SVC:
    api.create_namespaced_service('default', service)

    # Создаем mysql Deployment:
    api = kubernetes.client.AppsV1Api()
    api.create_namespaced_deployment('default', deployment)
    # Пытаемся восстановиться из backup
    try:
        api = kubernetes.client.BatchV1Api()
        api.create_namespaced_job('default', restore_job)
    except kubernetes.client.rest.ApiException:
        pass

    # Cоздаем PVC  и PV для бэкапов:
    try:
        backup_pv = render_template('backup-pv.yml.j2', {'name': name})
        api = kubernetes.client.CoreV1Api()
        print(api.create_persistent_volume(backup_pv))
        api.create_persistent_volume(backup_pv)
    except kubernetes.client.rest.ApiException:
        pass

    try:
        backup_pvc = render_template('backup-pvc.yml.j2', {'name': name})
        api = kubernetes.client.CoreV1Api()
        api.create_namespaced_persistent_volume_claim('default', backup_pvc)
    except kubernetes.client.rest.ApiException:
        pass


@kopf.on.delete('otus.homework', 'v1', 'mysqls')
def delete_object_make_backup(body, **kwargs):
    name = body['metadata']['name']
    image = body['spec']['image']
    password = body['spec']['password']
    database = body['spec']['database']

    delete_success_jobs(name)

    # Cоздаем backup job:
    api = kubernetes.client.BatchV1Api()
    backup_job = render_template('backup-job.yml.j2', {
        'name': name,
        'image': image,
        'password': password,
        'database': database})
    api.create_namespaced_job('default', backup_job)
    wait_until_job_end(f"backup-{name}-job")
    return {'message': "mysql and its children resources deleted"}
```

Вот и готово. Запускаем оператор (из директории build):

```console
kopf run mysql-operator.py
```

Создаем CR:

```console
kubectl apply -f deploy/cr.yml
```

```console
kopf run mysql-operator.py

  json_manifest = yaml.load(yaml_manifest)
{'api_version': 'v1',
 'kind': 'PersistentVolume',
 'metadata': {'annotations': None,
              'cluster_name': None,
              'creation_timestamp': datetime.datetime(2020, 6, 2, 11, 16, 39, tzinfo=tzutc()),
              'deletion_grace_period_seconds': None,
              'deletion_timestamp': None,
              'finalizers': ['kubernetes.io/pv-protection'],
              'generate_name': None,
              'generation': None,
              'initializers': None,
              'labels': {'pv-usage': 'backup-mysql-instance'},
              'managed_fields': [{'api_version': 'v1',
                                  'fields': None,
                                  'manager': 'OpenAPI-Generator',
                                  'operation': 'Update',
                                  'time': datetime.datetime(2020, 6, 2, 11, 16, 39, tzinfo=tzutc())}],
              'name': 'backup-mysql-instance-pv',
              'namespace': None,
              'owner_references': None,
              'resource_version': '4593',
              'self_link': '/api/v1/persistentvolumes/backup-mysql-instance-pv',
              'uid': '42e3cb0b-4b5f-463d-9171-3c618b059505'},
 'spec': {'access_modes': ['ReadWriteOnce'],
          'aws_elastic_block_store': None,
          'azure_disk': None,
          'azure_file': None,
          'capacity': {'storage': '1Gi'},
          'cephfs': None,
          'cinder': None,
          'claim_ref': None,
          'csi': None,
          'fc': None,
          'flex_volume': None,
          'flocker': None,
          'gce_persistent_disk': None,
          'glusterfs': None,
          'host_path': {'path': '/data/pv-backup/', 'type': ''},
          'iscsi': None,
          'local': None,
          'mount_options': None,
          'nfs': None,
          'node_affinity': None,
          'persistent_volume_reclaim_policy': 'Retain',
          'photon_persistent_disk': None,
          'portworx_volume': None,
          'quobyte': None,
          'rbd': None,
          'scale_io': None,
          'storage_class_name': None,
          'storageos': None,
          'volume_mode': 'Filesystem',
          'vsphere_volume': None},
 'status': {'message': None, 'phase': 'Pending', 'reason': None}}
[2020-06-02 14:16:39,502] kopf.objects         [INFO    ] [default/mysql-instance] Handler 'mysql_on_create' succeeded.
[2020-06-02 14:16:39,502] kopf.objects         [INFO    ] [default/mysql-instance] All handlers succeeded for creation.```
```

Проверяем что появились pvc:

```console
kubectl get pvc
NAME                        STATUS   VOLUME                     CAPACITY   ACCESS MODES   STORAGECLASS   AGE
backup-mysql-instance-pvc   Bound    backup-mysql-instance-pv   1Gi        RWO                           5s
mysql-instance-pvc          Bound    mysql-instance-pv          1Gi        RWO                           5s

kubectl get pv
NAME                       CAPACITY   ACCESS MODES   RECLAIM POLICY   STATUS   CLAIM                               STORAGECLASS   REASON   AGE
backup-mysql-instance-pv   1Gi        RWO            Retain           Bound    default/backup-mysql-instance-pvc                           7s
mysql-instance-pv          1Gi        RWO            Retain           Bound    default/mysql-instance-pvc                                  7s
```

Проверим, что все работает, для этого заполним базу созданного mysqlinstance:

```console
export MYSQLPOD=$(kubectl get pods -l app=mysql-instance -o jsonpath="{.items[*].metadata.name}")

kubectl exec -it $MYSQLPOD -- mysql -u root -potuspassword -e "CREATE TABLE test (id smallint unsigned not null auto_increment, name varchar(20) not null, constraint pk_example primary key (id) );" otus-database
mysql: [Warning] Using a password on the command line interface can be insecure.

kubectl exec -it $MYSQLPOD -- mysql -potuspassword -e "INSERT INTO test ( id, name) VALUES ( null, 'some data' );" otus-database
mysql: [Warning] Using a password on the command line interface can be insecure.

kubectl exec -it $MYSQLPOD -- mysql -potuspassword -e "INSERT INTO test ( id, name) VALUES ( null, 'some data-2' );" otus-database


kubectl exec -it $MYSQLPOD -- mysql -potuspassword -e "INSERT INTO test ( id, name) VALUES ( null, 'some data-2' );" otus-database
mysql: [Warning] Using a password on the command line interface can be insecure.


kubectl exec -it $MYSQLPOD -- mysql -potuspassword -e "select * from test;" otus-database
mysql: [Warning] Using a password on the command line interface can be insecure.
+----+-------------+
| id | name        |
+----+-------------+
|  1 | some data   |
|  2 | some data-2 |
+----+-------------+
```

Удалим mysql-instance:

```console
kubectl delete mysqls.otus.homework mysql-instance
mysql.otus.homework "mysql-instance" deleted
```

Теперь kubectl get pv показывает, что PV для mysql больше нет, а kubectl get jobs.batch показывает:

```console
kubectl get pv
NAME                       CAPACITY   ACCESS MODES   RECLAIM POLICY   STATUS        CLAIM                               STORAGECLASS   REASON   AGE
backup-mysql-instance-pv   1Gi        RWO            Retain           Bound         default/backup-mysql-instance-pvc                           5m49s
mysql-instance-pv          1Gi        RWO            Retain           Terminating   default/mysql-instance-pvc                                  5m49s


kubectl get jobs.batch
NAME                        COMPLETIONS   DURATION   AGE
backup-mysql-instance-job   1/1           1s         36s
```

> Если Job не выполнилась или выполнилась с ошибкой, то ее нужно удалять в ручную, т к иногда полезно посмотреть логи

Создадим заново mysql-instance:

```console
kubectl apply -f cr.yml  
mysql.otus.homework/mysql-instance created
```

Немного подождем и:

```console
export MYSQLPOD=$(kubectl get pods -l app=mysql-instance -o jsonpath="{.items[*].metadata.name}")

kubectl exec -it $MYSQLPOD -- mysql -potuspassword -e "select * from test;" otus-database
mysql: [Warning] Using a password on the command line interface can be insecure.
+----+-------------+
| id | name        |
+----+-------------+
|  1 | some data   |
|  2 | some data-2 |
+----+-------------+
```

Мы убедились, что наш контроллер работает, теперь нужно его остановить и собрать Docker образ с ним. В директории build создадим Dockerfile:

```Dockerfile
FROM python:3.7
COPY templates ./templates
COPY mysql-operator.py ./mysql-operator.py
RUN pip install kopf kubernetes pyyaml jinja2
CMD kopf run /mysql-operator.py
```

Соберем и сделаем push в dockerhub наш образ с оператором:

```console
docker build -t kovtalex/mysql-operator:0.1 .
docker push kovtalex/mysql-operator:0.1
```

### Деплой оператора

Создадим и применим манифесты в папке kubernetes-operator/deploy:

- service-account.yml
- role.yml
- role-binding.yml
- deploy-operator.yml

```console
kubectl apply -f role.yml -f service-account.yml -f role-binding.yml -f deploy-operator.yml
clusterrole.rbac.authorization.k8s.io/mysql-operator created
serviceaccount/mysql-operator created
clusterrolebinding.rbac.authorization.k8s.io/workshop-operator created
deployment.apps/mysql-operator created
```

### Проверим, что все работает

Создаем CR (если еще не создан):

```console
kubectl apply -f deploy/cr.yml
```

Проверяем что появились pvc:

```console
kubectl get pvc
NAME                        STATUS   VOLUME                     CAPACITY   ACCESS MODES   STORAGECLASS   AGE
backup-mysql-instance-pvc   Bound    backup-mysql-instance-pv   1Gi        RWO                           19m
mysql-instance-pvc          Bound    mysql-instance-pv          1Gi        RWO                           8m14s
```

Заполним базу созданного mysql-instance:

```console
export MYSQLPOD=$(kubectl get pods -l app=mysql-instance -o jsonpath="{.items[*].metadata.name}")

kubectl exec -it $MYSQLPOD -- mysql -potuspassword -e "select * from test;" otus-database
mysql: [Warning] Using a password on the command line interface can be insecure.
+----+-------------+
| id | name        |
+----+-------------+
|  1 | some data   |
|  2 | some data-2 |
+----+-------------+
```

Удалим mysql-instance:

```console
kubectl delete mysqls.otus.homework mysql-instance
mysql.otus.homework "mysql-instance" deleted
```

Теперь kubectl get pv показывает, что PV для mysql больше нет, а kubectl get jobs.batch показывает:

```console
kubectl get pv
NAME                       CAPACITY   ACCESS MODES   RECLAIM POLICY   STATUS   CLAIM                               STORAGECLASS   REASON   AGE
backup-mysql-instance-pv   1Gi        RWO            Retain           Bound    default/backup-mysql-instance-pvc                           22m

kubectl get jobs.batch
NAME                        COMPLETIONS   DURATION   AGE
backup-mysql-instance-job   1/1           1s         28s
```

> Если Job не выполнилась или выполнилась с ошибкой, то ее нужно удалять в ручную, т к иногда полезно посмотреть логи

Создадим заново mysql-instance:

```console
kubectl apply -f deploy/cr.yml
```

Немного подождем и:

```console
export MYSQLPOD=$(kubectl get pods -l app=mysql-instance -o jsonpath="{.items[*].metadata.name}")
kubectl exec -it $MYSQLPOD -- mysql -potuspassword -e "select * from test;" otus-database
mysql: [Warning] Using a password on the command line interface can be insecure.
+----+-------------+
| id | name        |
+----+-------------+
|  1 | some data   |
|  2 | some data-2 |
+----+-------------+
```

### Проверка | tree

Содержимое папки kubernetes-operators:

```console
tree kubernetes-operators

kubernetes-operators
├── build
│   ├── Dockerfile
│   ├── mysql-operator.py
│   └── templates
│       ├── backup-job.yml.j2
│       ├── backup-pv.yml.j2
│       ├── backup-pvc.yml.j2
│       ├── mysql-deployment.yml.j2
│       ├── mysql-pv.yml.j2
│       ├── mysql-pvc.yml.j2
│       ├── mysql-service.yml.j2
│       └── restore-job.yml.j2
└── deploy
    ├── cr.yml
    ├── crd.yml
    ├── deploy-operator.yml
    ├── role-binding.yml
    ├── role.yml
    └── service-account.yml
```

Результаты:

```console
kubectl get jobs
NAME                         COMPLETIONS   DURATION   AGE
backup-mysql-instance-job    1/1           1s         4m53s
restore-mysql-instance-job   1/1           38s        3m58s

export MYSQLPOD=$(kubectl get pods -l app=mysql-instance -o jsonpath="{.items[*].metadata.name}")
kubectl exec -it $MYSQLPOD -- mysql -potuspassword -e "select * from test;" otus-database
mysql: [Warning] Using a password on the command line interface can be insecure.
+----+-------------+
| id | name        |
+----+-------------+
|  1 | some data   |
|  2 | some data-2 |
+----+-------------+
```

## Шаблонизация манифестов Kubernetes

### Intro

Домашнее задание выполняем в GKE кластере.  
Для доступа к Google Cloud Platform нужно активировать триальный аккаунт в GCP.

[Официальная документация](https://cloud.google.com/kubernetes-engine/)

```console
gcloud container clusters get-credentials cluster-1 --zone europe-west1-b --project angular-pursuit-275120
etching cluster endpoint and auth data.
kubeconfig entry generated for cluster1.
```

### Устанавливаем готовые Helm charts

Попробуем установить Helm charts созданные сообществом. С их помощью создадим и настроим инфраструктурные сервисы, необходимые для работы нашего кластера.

Для установки будем использовать **Helm 3**.

Сегодня будем работать со следующими сервисами:

- [nginx-ingress](https://github.com/helm/charts/tree/master/stable/nginx-ingress) - сервис, обеспечивающий доступ к публичным ресурсам кластера
- [cert-manager](https://github.com/jetstack/cert-manager/tree/master/deploy/charts/cert-manager) - сервис, позволяющий динамически генерировать Let's Encrypt сертификаты для ingress ресурсов
- [chartmuseum](https://github.com/helm/charts/tree/master/stable/chartmuseum) - специализированный репозиторий для хранения helm charts
- [harbor](https://github.com/goharbor/harbor-helm) - хранилище артефактов общего назначения (Docker Registry), поддерживающее helm charts

### Установка Helm 3

Для начала нам необходимо установить **Helm 3** на локальную машину.  
Инструкции по установке можно найти по [ссылке](https://github.com/helm/helm#install).

```console
brew install helm
```

Критерий успешности установки - после выполнения команды вывод:

```console
helm version
version.BuildInfo{Version:"v3.2.1", GitCommit:"fe51cd1e31e6a202cba7dead9552a6d418ded79a", GitTreeState:"clean", GoVersion:"go1.13.10"}
```

### Памятка по использованию Helm

Создание **release**:

```console
helm install <chart_name> --name=<release_name> --namespace=<namespace>
kubectl get secrets -n <namespace> | grep <release_name>
```

Обновление **release**:

```console
helm upgrade <release_name> <chart_name> --namespace=<namespace>
kubectl get secrets -n <namespace> | grep <release_name>
```

Создание или обновление **release**:

```console
helm upgrade --install <release_name> <chart_name> --namespace=<namespace>
kubectl get secrets -n <namespace> | grep <release_name>
```

### Add helm repo

Добавим репозиторий stable

По умолчанию в **Helm 3** не установлен репозиторий stable

```console
helm repo add stable https://kubernetes-charts.storage.googleapis.com
"stable" has been added to your repositories

helm repo list
NAME    URL
stable  https://kubernetes-charts.storage.googleapis.com
```

### nginx-ingress

Создадим *namespace* и **release** [nginx-ingress](https://cert-manager.io/next-docs/installation/kubernetes/)

```console
kubectl create ns nginx-ingress
namespace/nginx-ingress created

helm upgrade --install nginx-ingress stable/nginx-ingress --wait \
--namespace=nginx-ingress \
--version=1.39.0


Release "nginx-ingress" does not exist. Installing it now.
NAME: nginx-ingress
LAST DEPLOYED: Wed May 27 22:15:54 2020
NAMESPACE: nginx-ingress
STATUS: deployed
REVISION: 1
TEST SUITE: None
NOTES:
The nginx-ingress controller has been installed.
It may take a few minutes for the LoadBalancer IP to be available.
You can watch the status by running 'kubectl --namespace nginx-ingress get services -o wide -w nginx-ingress-controller'

An example Ingress that makes use of the controller:

  apiVersion: extensions/v1beta1
  kind: Ingress
  metadata:
    annotations:
      kubernetes.io/ingress.class: nginx
    name: example
    namespace: foo
  spec:
    rules:
      - host: www.example.com
        http:
          paths:
            - backend:
                serviceName: exampleService
                servicePort: 80
              path: /
    # This section is only required if TLS is to be enabled for the Ingress
    tls:
        - hosts:
            - www.example.com
          secretName: example-tls

If TLS is enabled for the Ingress, a Secret containing the certificate and key must also be provided:

  apiVersion: v1
  kind: Secret
  metadata:
    name: example-tls
    namespace: foo
  data:
    tls.crt: <base64 encoded cert>
    tls.key: <base64 encod
```

Разберем используемые ключи:

- **--wait** - ожидать успешного окончания установки ([подробности](https://helm.sh/docs/using_helm/#helpful-options-for-install-upgrade-rollback))
- **--timeout** - считать установку неуспешной по истечении указанного времени
- **--namespace** - установить chart в определенный namespace (если не существует, необходимо создать)
- **--version** - установить определенную версию chart

### cert-manager

Добавим репозиторий, в котором хранится актуальный helm chart cert-manager:

```console
helm repo add jetstack https://charts.jetstack.io
"jetstack" has been added to your repositories

helm repo update
Hang tight while we grab the latest from your chart repositories...
...Successfully got an update from the "jetstack" chart repository
...Successfully got an update from the "stable" chart repository
Update Complete. ⎈ Happy Helming!⎈
```

Создадим namespace

```console
kubectl create namespace cert-manager
namespace/cert-manager created
```

Также для установки cert-manager предварительно потребуется создать в кластере некоторые **CRD**:

```console
kubectl apply --validate=false -f https://github.com/jetstack/cert-manager/releases/download/v0.15.0/cert-manager.crds.yaml
customresourcedefinition.apiextensions.k8s.io/certificaterequests.cert-manager.io created
customresourcedefinition.apiextensions.k8s.io/certificates.cert-manager.io created
customresourcedefinition.apiextensions.k8s.io/challenges.acme.cert-manager.io created
customresourcedefinition.apiextensions.k8s.io/clusterissuers.cert-manager.io created
customresourcedefinition.apiextensions.k8s.io/issuers.cert-manager.io created
customresourcedefinition.apiextensions.k8s.io/orders.acme.cert-manager.io created
```

Установим cert-manager:

```console
helm install cert-manager jetstack/cert-manager --namespace cert-manager --version v0.15.1

NAME: cert-manager
LAST DEPLOYED: Wed May 27 22:19:16 2020
NAMESPACE: cert-manager
STATUS: deployed
REVISION: 1
TEST SUITE: None
NOTES:
cert-manager has been deployed successfully!

In order to begin issuing certificates, you will need to set up a ClusterIssuer
or Issuer resource (for example, by creating a 'letsencrypt-staging' issuer).

More information on the different types of issuers and how to configure them
can be found in our documentation:

https://cert-manager.io/docs/configuration/

For information on how to configure cert-manager to automatically provision
Certificates for Ingress resources, take a look at the `ingress-shim`
documentation:

https://cert-manager.io/docs/usage/ingress/
```

Проверим, что cert-manager успешно развернут и работает:

```console
kubectl get pods --namespace cert-manager

NAME                                       READY   STATUS    RESTARTS   AGE
cert-manager-766d5c494b-d9mkq              1/1     Running   0          14s
cert-manager-cainjector-6649bbb695-cpk46   1/1     Running   0          14s
cert-manager-webhook-68d464c8b-9mfpv       1/1     Running   0          14s

cat <<EOF > test-resources.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: cert-manager-test
---
apiVersion: cert-manager.io/v1alpha2
kind: Issuer
metadata:
  name: test-selfsigned
  namespace: cert-manager-test
spec:
  selfSigned: {}
---
apiVersion: cert-manager.io/v1alpha2
kind: Certificate
metadata:
  name: selfsigned-cert
  namespace: cert-manager-test
spec:
  dnsNames:
    - example.com
  secretName: selfsigned-cert-tls
  issuerRef:


kubectl apply -f test-resources.yaml
namespace/cert-manager-test created
issuer.cert-manager.io/test-selfsigned created
certificate.cert-manager.io/selfsigned-cert created


kubectl describe certificate -n cert-manager-test

Name:         selfsigned-cert
Namespace:    cert-manager-test
Labels:       <none>
Annotations:  kubectl.kubernetes.io/last-applied-configuration:
                {"apiVersion":"cert-manager.io/v1alpha2","kind":"Certificate","metadata":{"annotations":{},"name":"selfsigned-cert","namespace":"cert-mana...
API Version:  cert-manager.io/v1alpha3
Kind:         Certificate
Metadata:
  Creation Timestamp:  2020-05-27T19:20:40Z
  Generation:          1
  Resource Version:    3879
  Self Link:           /apis/cert-manager.io/v1alpha3/namespaces/cert-manager-test/certificates/selfsigned-cert
  UID:                 2166b2f3-faf7-4fe5-a9e4-410f4540effc
Spec:
  Dns Names:
    example.com
  Issuer Ref:
    Name:       test-selfsigned
  Secret Name:  selfsigned-cert-tls
Status:
  Conditions:
    Last Transition Time:  2020-05-27T19:20:41Z
    Message:               Certificate is up to date and has not expired
    Reason:                Ready
    Status:                True
    Type:                  Ready
  Not After:               2020-08-25T19:20:41Z
Events:
  Type    Reason        Age   From          Message
  ----    ------        ----  ----          -------
  Normal  GeneratedKey  11s   cert-manager  Generated a new private key
  Normal  Requested     11s   cert-manager  Created new CertificateRequest resource "selfsigned-cert-504566127"
  Normal  Issued        11s   cert-manager  Certificate issued successfully


kubectl delete -f test-resources.yaml
namespace "cert-manager-test" deleted
issuer.cert-manager.io "test-selfsigned" deleted
```

### cert-manager | Самостоятельное задание

Для выпуска сертификатов нам потребуются ClusterIssuers. Создадим их для staging и production окружений.

cluster-issuer-prod.yaml:

```yml
apiVersion: cert-manager.io/v1alpha2
kind: ClusterIssuer
metadata:
  name: letsencrypt-production
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: kovtalex@gmail.com
    privateKeySecretRef:
      name: letsencrypt-production
    solvers:
    - http01:
        ingress:
          class:  nginx
```

cluster-issuer-stage.yaml:

```yml
apiVersion: cert-manager.io/v1alpha2
kind: ClusterIssuer
metadata:
  name: letsencrypt-staging
spec:
  acme:
    server: https://acme-staging-v02.api.letsencrypt.org/directory
    email: kovtalex@gmail.com
    privateKeySecretRef:
      name: letsencrypt-staging
    solvers:
    - http01:
        ingress:
          class:  nginx
```

Проверим статус:

```console
kubectl describe clusterissuers -n cert-manager
Name:         letsencrypt-production
Namespace:
Labels:       app=raw
              app.kubernetes.io/managed-by=Helm
              chart=raw-0.2.3
              heritage=Helm
              release=cert-manager-issuers
Annotations:  meta.helm.sh/release-name: cert-manager-issuers
              meta.helm.sh/release-namespace: cert-manager
API Version:  cert-manager.io/v1alpha3
Kind:         ClusterIssuer
Metadata:
  Creation Timestamp:  2020-05-30T17:09:38Z
  Generation:          1
  Resource Version:    1274031
  Self Link:           /apis/cert-manager.io/v1alpha3/clusterissuers/letsencrypt-production
  UID:                 6491edb5-382c-48a9-bc92-a000342dc334
Spec:
  Acme:
    Email:  kovtalex@gmail.com
    Private Key Secret Ref:
      Name:  letsencrypt-production
    Server:  https://acme-v02.api.letsencrypt.org/directory
    Solvers:
      http01:
        Ingress:
          Class:  nginx
Status:
  Acme:
    Last Registered Email:  kovtalex@gmail.com
    Uri:                    https://acme-v02.api.letsencrypt.org/acme/acct/87525196
  Conditions:
    Last Transition Time:  2020-05-30T17:09:47Z
    Message:               The ACME account was registered with the ACME server
    Reason:                ACMEAccountRegistered
    Status:                True
    Type:                  Ready
Events:                    <none>


Name:         letsencrypt-staging
Namespace:
Labels:       app=raw
              app.kubernetes.io/managed-by=Helm
              chart=raw-0.2.3
              heritage=Helm
              release=cert-manager-issuers
Annotations:  meta.helm.sh/release-name: cert-manager-issuers
              meta.helm.sh/release-namespace: cert-manager
API Version:  cert-manager.io/v1alpha3
Kind:         ClusterIssuer
Metadata:
  Creation Timestamp:  2020-05-30T17:09:38Z
  Generation:          1
  Resource Version:    1274029
  Self Link:           /apis/cert-manager.io/v1alpha3/clusterissuers/letsencrypt-staging
  UID:                 29366949-a45a-458f-bea1-95d7cd74773a
Spec:
  Acme:
    Email:  kovtalex@gmail.com
    Private Key Secret Ref:
      Name:  letsencrypt-staging
    Server:  https://acme-staging-v02.api.letsencrypt.org/directory
    Solvers:
      http01:
        Ingress:
          Class:  nginx
Status:
  Acme:
    Last Registered Email:  kovtalex@gmail.com
    Uri:                    https://acme-staging-v02.api.letsencrypt.org/acme/acct/13939356
  Conditions:
    Last Transition Time:  2020-05-30T17:09:47Z
    Message:               The ACME account was registered with the ACME server
    Reason:                ACMEAccountRegistered
    Status:                True
    Type:                  Ready
Events:                    <none>
```

### chartmuseum

Кастомизируем установку chartmuseum

- Создадим директорию kubernetes-templating/chartmuseum/ и поместим туда файл values.yaml
- Изучим [содержимое](https://github.com/helm/charts/blob/master/stable/chartmuseum/values.yaml) оригинальный файла values.yaml
- Включим:
  - Создание ingress ресурса с корректным hosts.name (должен использоваться nginx-ingress)
  - Автоматическую генерацию Let's Encrypt сертификата

<https://github.com/helm/charts/tree/master/stable/chartmuseum>

Файл values.yaml для chartmuseum будет выглядеть следующим образом:

```yml
ingress:
  enabled: true
  annotations:
    kubernetes.io/ingress.class: "nginx"
    cert-manager.io/cluster-issuer: "letsencrypt-production"
  hosts:
    - name: chartmuseum.35.189.202.237.nip.io
      path: /
      tls: true
      tlsSecret: chartmuseum.35.189.202.237.nip.io
securityContext: {}
env:
  open:
    DISABLE_API: false
```

Установим chartmuseum:

```console
kubectl create ns chartmuseum
namespace/chartmuseum created

helm upgrade --install chartmuseum stable/chartmuseum --wait --version=2.13.0  --namespace=chartmuseum -f kubernetes-templating/chartmuseum/values.yaml
Release "chartmuseum" has been upgraded. Happy Helming!
NAME: chartmuseum
LAST DEPLOYED: Thu May 28 14:24:55 2020
NAMESPACE: chartmuseum
STATUS: deployed
REVISION: 3
TEST SUITE: None
NOTES:
** Please be patient while the chart is being deployed **

Get the ChartMuseum URL by running:

  export POD_NAME=$(kubectl get pods --namespace chartmuseum -l "app=chartmuseum" -l "release=chartmuseum" -o jsonpath="{.items[0].metadata.name}")
  echo http://127.0.0.1:8080/
  kubectl port-forward $POD_NAME 8080:8080 --namespace chartmuseum
```

Проверим, что release chartmuseum установился:

```console
helm ls -n chartmuseum
NAME            NAMESPACE       REVISION        UPDATED                                 STATUS          CHART                   APP VERSION
chartmuseum     chartmuseum     1               2020-05-27 22:23:39.234698 +0300 MSK    deployed        chartmuseum-2.13.0      0.12.0
```

- **helm 2** хранил информацию о релизе в configMap'ах (kubectl get configmaps -n kube-system)
- **Helm 3** хранит информацию в secrets (kubectl get secrets - n chartmuseum)

```console
kubectl get secrets -n chartmuseum

NAME                                TYPE                                  DATA   AGE
chartmuseum-chartmuseum             Opaque                                0      9m17s
chartmuseum.35.189.202.237.nip.io   kubernetes.io/tls                     3      9m16s
default-token-cxhw9                 kubernetes.io/service-account-token   3      9m25s
sh.helm.release.v1.chartmuseum.v1   helm.sh/release.v1                    1      9m17s
```

Проверяем: <https://chartmuseum.35.240.96.124.nip.io>

### chartmuseum | Задание со ⭐

Научимся работать с chartmuseum и зальем в наш репозиторий - примеру frontend

- Добавяем наш репозитарий

```console
helm repo add chartmuseum https://chartmuseum.35.189.202.237.nip.io/
"chartmuseum" has been added to your repositories
```

- Проверяем линтером

```console
helm lint
==> Linting .
[INFO] Chart.yaml: icon is recommended

1 chart(s) linted, 0 chart(s) failed
```

- Пакуем

```consol
helm package .
Successfully packaged chart and saved it to: /Users/alexey/kovtalex_platform/kubernetes-templating/frontend/frontend-0.1.0.tgz
```

- Заливаем

```console
curl -L --data-binary "@frontend-0.1.0.tgz" https://chartmuseum.35.189.202.237.nip.io/api/charts
{"saved":true}
```

- Обновляем список repo

```console
helm repo update
Hang tight while we grab the latest from your chart repositories...
...Successfully got an update from the "harbor" chart repository
...Successfully got an update from the "chartmuseum" chart repository
...Successfully got an update from the "templating" chart repository
...Successfully got an update from the "jetstack" chart repository
...Successfully got an update from the "stable" chart repository
Update Complete. ⎈ Happy Helming!⎈
```

- Ищем наш frontend в репозитории

```console
helm search repo -l chartmuseum/
NAME                    CHART VERSION   APP VERSION     DESCRIPTION
chartmuseum/frontend    0.1.0           1.16.0          A Helm chart for Kubernetes
```

- И выкатываем

```console
helm upgrade --install frontend chartmuseum/frontend --namespace hipster-shop
Release "frontend" does not exist. Installing it now.
NAME: frontend
LAST DEPLOYED: Sat May 30 01:59:17 2020
NAMESPACE: hipster-shop
STATUS: deployed
REVISION: 1
TEST SUITE: None
```

### Harbor

Установим [Harbor](https://github.com/goharbor/harbor-helm)

- Пишем values.yaml

```yml
 expose:
  type: ingress
  tls:
    enables: true
    secretName: harbor.35.189.202.237.nip.io
    notarySecretName: notary.35.189.202.237.nip.io
  ingress:
    hosts:
      core: harbor.35.189.202.237.nip.io
    annotations:
      kubernetes.io/ingress.class: "nginx"
      cert-manager.io/cluster-issuer: "letsencrypt-production"
notary:
  enabled: false
```

- Добавляем repo

```console
helm repo add harbor https://helm.goharbor.io
"harbor" has been added to your repositories
````

- Обновляем repo

```console
helm repo update
Hang tight while we grab the latest from your chart repositories...
...Successfully got an update from the "harbor" chart repository
...Successfully got an update from the "jetstack" chart repository
...Successfully got an update from the
```

- Создаем ns

```console
kubectl create ns harbor
namespace/harbor created
```

- Выкатывем

```console
helm upgrade --install harbor harbor/harbor --wait --namespace=harbor-system --version=1.3.2 -f kubernetes-templating/harbor/values.yaml
Release "harbor" does not exist. Installing it now.
NAME: harbor
LAST DEPLOYED: Thu May 28 23:35:35 2020
NAMESPACE: harbor-system
STATUS: deployed
REVISION: 1
TEST SUITE: None
NOTES:
Please wait for several minutes for Harbor deployment to complete.
Then you should be able to visit the Harbor portal at https://core.harbor.domain.
For more details, please visit https://github.com/goharbor/harbor.
```

#### Tips & Tricks

- Формат описания переменных в файле values.yaml для **chartmuseum** и **harbor** отличается
- Helm3 не создает namespace в который будет установлен release
- Проще выключить сервис **notary**, он нам не понадобится
- Реквизиты по умолчанию - **admin/Harbor12345**
- nip.io может оказаться забанен в cert-manager. Если у вас есть собственный домен - лучше использовать его, либо попробовать xip.io, либо переключиться на staging ClusterIssuer
- Обратим внимание, как helm3 хранит информацию о release: kubectl get secrets -n harbor -l owner=helm

Проверяем: <https://harbor.35.189.202.237.nip.io/>

### Используем helmfile | Задание со ⭐

Опишем установку **nginx-ingress**, **cert-manager** и **harbor** в helmfile

- Установим helmfile

```console
brew install helmfile
```

> Для применения манифестов ClusterIssuers воспользуемся [incubator/raw](https://hub.helm.sh/charts/incubator/raw/0.2.3) - A place for all the Kubernetes resources which don't already have a home.

Пилим helmfile.yaml

```yml
repositories:
- name: stable
  url: https://kubernetes-charts.storage.googleapis.com
- name: jetstack
  url: https://charts.jetstack.io
- name: harbor
  url: https://helm.goharbor.io
- name: incubator
  url: https://kubernetes-charts-incubator.storage.googleapis.com


helmDefaults:
  wait: true

releases:
- name: cert-manager
  namespace: cert-manager
  chart: jetstack/cert-manager
  version: v0.15.1
  set:
  - name: installCRDs
    value: true

- name: cert-manager-issuers
  needs:
    - cert-manager/cert-manager
  namespace: cert-manager
  chart: incubator/raw
  version: 0.2.3
  values:
    - ./cert-manager/values.yaml

- name: harbor
  needs:
    - cert-manager/cert-manager
  namespace: harbor
  chart: harbor/harbor
  version: 1.3.2
  values:
    - ./harbor/values.yaml

- name: chartmuseum
  needs:
    - cert-manager/cert-manager
  namespace: chartmuseum
  chart: stable/chartmuseum
  version: 2.13.0
  values:
    - ./chartmuseum/values.yaml
```

- Проверим отсутствие ns наших сервисов

```console
kubectl get ns
NAME              STATUS   AGE
default           Active   2d21h
kube-node-lease   Active   2d21h
kube-public       Active   2d21h
kube-system       Active   2d21h
```

- Линтим

```console
helmfile lint

Fetching incubator/raw
Fetching jetstack/cert-manager
Fetching harbor/harbor
Fetching stable/chartmuseum
Adding repo stable https://kubernetes-charts.storage.googleapis.com
"stable" has been added to your repositories

Adding repo jetstack https://charts.jetstack.io
"jetstack" has been added to your repositories

Adding repo harbor https://helm.goharbor.io
"harbor" has been added to your repositories

Adding repo incubator https://kubernetes-charts-incubator.storage.googleapis.com
"incubator" has been added to your repositories

Updating repo
Hang tight while we grab the latest from your chart repositories...
...Successfully got an update from the "jetstack" chart repository
...Successfully got an update from the "incubator" chart repository
...Successfully got an update from the "harbor" chart repository
...Successfully got an update from the "stable" chart repository
Update Complete. ⎈ Happy Helming!⎈

Building dependency release=cert-manager, chart=/var/folders/kq/byg7brhj5g39gnj_66sp02z00000gn/T/077869428/cert-manager/v0.15.1/jetstack/cert-manager/cert-manager
Building dependency release=cert-manager-issuers, chart=/var/folders/kq/byg7brhj5g39gnj_66sp02z00000gn/T/077869428/cert-manager-issuers/0.2.3/incubator/raw/raw
Building dependency release=harbor, chart=/var/folders/kq/byg7brhj5g39gnj_66sp02z00000gn/T/077869428/harbor/1.3.2/harbor/harbor/harbor
Building dependency release=chartmuseum, chart=/var/folders/kq/byg7brhj5g39gnj_66sp02z00000gn/T/077869428/chartmuseum/2.13.0/stable/chartmuseum/chartmuseum
Linting release=cert-manager, chart=/var/folders/kq/byg7brhj5g39gnj_66sp02z00000gn/T/077869428/cert-manager/v0.15.1/jetstack/cert-manager/cert-manager
==> Linting /var/folders/kq/byg7brhj5g39gnj_66sp02z00000gn/T/077869428/cert-manager/v0.15.1/jetstack/cert-manager/cert-manager

1 chart(s) linted, 0 chart(s) failed

Linting release=cert-manager-issuers, chart=/var/folders/kq/byg7brhj5g39gnj_66sp02z00000gn/T/077869428/cert-manager-issuers/0.2.3/incubator/raw/raw
==> Linting /var/folders/kq/byg7brhj5g39gnj_66sp02z00000gn/T/077869428/cert-manager-issuers/0.2.3/incubator/raw/raw
[INFO] Chart.yaml: icon is recommended

1 chart(s) linted, 0 chart(s) failed

Linting release=harbor, chart=/var/folders/kq/byg7brhj5g39gnj_66sp02z00000gn/T/077869428/harbor/1.3.2/harbor/harbor/harbor
==> Linting /var/folders/kq/byg7brhj5g39gnj_66sp02z00000gn/T/077869428/harbor/1.3.2/harbor/harbor/harbor

1 chart(s) linted, 0 chart(s) failed

Linting release=chartmuseum, chart=/var/folders/kq/byg7brhj5g39gnj_66sp02z00000gn/T/077869428/chartmuseum/2.13.0/stable/chartmuseum/chartmuseum
==> Linting /var/folders/kq/byg7brhj5g39gnj_66sp02z00000gn/T/077869428/chartmuseum/2.13.0/stable/chartmuseum/chartmuseum

1 chart(s) linted, 0 chart(s) failed
```

- Устанавлием nginx-ingress, cert-manager и harbor

```console
helmfile sync
Adding repo stable https://kubernetes-charts.storage.googleapis.com
"stable" has been added to your repositories

Adding repo jetstack https://charts.jetstack.io
"jetstack" has been added to your repositories

Adding repo harbor https://helm.goharbor.io
"harbor" has been added to your repositories

Adding repo incubator https://kubernetes-charts-incubator.storage.googleapis.com
"incubator" has been added to your repositories

Updating repo
Hang tight while we grab the latest from your chart repositories...
...Successfully got an update from the "jetstack" chart repository
...Successfully got an update from the "incubator" chart repository
...Successfully got an update from the "harbor" chart repository
...Successfully got an update from the "stable" chart repository
Update Complete. ⎈ Happy Helming!⎈

Affected releases are:
  cert-manager (jetstack/cert-manager) UPDATED
  cert-manager-issuers (incubator/raw) UPDATED
  chartmuseum (stable/chartmuseum) UPDATED
  harbor (harbor/harbor) UPDATED

Upgrading release=cert-manager, chart=jetstack/cert-manager
Release "cert-manager" has been upgraded. Happy Helming!
NAME: cert-manager
LAST DEPLOYED: Sat May 30 20:11:38 2020
NAMESPACE: cert-manager
STATUS: deployed
REVISION: 4
TEST SUITE: None
NOTES:
cert-manager has been deployed successfully!

In order to begin issuing certificates, you will need to set up a ClusterIssuer
or Issuer resource (for example, by creating a 'letsencrypt-staging' issuer).

More information on the different types of issuers and how to configure them
can be found in our documentation:

https://cert-manager.io/docs/configuration/

For information on how to configure cert-manager to automatically provision
Certificates for Ingress resources, take a look at the `ingress-shim`
documentation:

https://cert-manager.io/docs/usage/ingress/

Listing releases matching ^cert-manager$
cert-manager    cert-manager    4               2020-05-30 20:11:38.415808 +0300 MSK    deployed        cert-manager-v0.15.1    v0.15.1

Upgrading release=cert-manager-issuers, chart=incubator/raw
Upgrading release=chartmuseum, chart=stable/chartmuseum
Upgrading release=harbor, chart=harbor/harbor
Release "cert-manager-issuers" has been upgraded. Happy Helming!
NAME: cert-manager-issuers
LAST DEPLOYED: Sat May 30 20:11:53 2020
NAMESPACE: cert-manager
STATUS: deployed
REVISION: 4
TEST SUITE: None

Listing releases matching ^cert-manager-issuers$
cert-manager-issuers    cert-manager    4               2020-05-30 20:11:53.680654 +0300 MSK    deployed        raw-0.2.3       0.2.3

Release "chartmuseum" does not exist. Installing it now.
NAME: chartmuseum
LAST DEPLOYED: Sat May 30 20:11:54 2020
NAMESPACE: chartmuseum
STATUS: deployed
REVISION: 1
TEST SUITE: None
NOTES:
** Please be patient while the chart is being deployed **

Get the ChartMuseum URL by running:

  export POD_NAME=$(kubectl get pods --namespace chartmuseum -l "app=chartmuseum" -l "release=chartmuseum" -o jsonpath="{.items[0].metadata.name}")
  echo http://127.0.0.1:8080/
  kubectl port-forward $POD_NAME 8080:8080 --namespace chartmuseum

Listing releases matching ^chartmuseum$
chartmuseum     chartmuseum     1               2020-05-30 20:11:54.450653 +0300 MSK    deployed        chartmuseum-2.13.0      0.12.0

Release "harbor" does not exist. Installing it now.
NAME: harbor
LAST DEPLOYED: Sat May 30 20:11:53 2020
NAMESPACE: harbor
STATUS: deployed
REVISION: 1
TEST SUITE: None
NOTES:
Please wait for several minutes for Harbor deployment to complete.
Then you should be able to visit the Harbor portal at https://core.harbor.domain.
For more details, please visit https://github.com/goharbor/harbor.

Listing releases matching ^harbor$
harbor  harbor          1               2020-05-30 20:11:53.628585 +0300 MSK    deployed        harbor-1.3.2    1.10.2


UPDATED RELEASES:
NAME                   CHART                   VERSION
cert-manager           jetstack/cert-manager   v0.15.1
cert-manager-issuers   incubator/raw             0.2.3
chartmuseum            stable/chartmuseum       2.13.0
harbor                 harbor/harbor             1.3.2
```

- Проверяем:

```console
kubectl get certificate --all-namespaces
NAMESPACE     NAME                                READY   SECRET                              AGE
chartmuseum   chartmuseum.35.189.202.237.nip.io   True    chartmuseum.35.189.202.237.nip.io   2m14s
harbor        harbor.35.189.202.237.nip.io        True    harbor.35.189.202.237.nip.io        2m11s

kubectl get deployments --all-namespaces
NAMESPACE       NAME                                       READY   UP-TO-DATE   AVAILABLE   AGE
cert-manager    cert-manager                               1/1     1            1           3m14s
cert-manager    cert-manager-cainjector                    1/1     1            1           3m14s
cert-manager    cert-manager-webhook                       1/1     1            1           3m14s
chartmuseum     chartmuseum-chartmuseum                    1/1     1            1           3m14s
harbor          harbor-harbor-chartmuseum                  1/1     1            1           3m11s
harbor          harbor-harbor-clair                        1/1     1            1           3m11s
harbor          harbor-harbor-core                         1/1     1            1           3m11s
harbor          harbor-harbor-jobservice                   1/1     1            1           3m11s
harbor          harbor-harbor-notary-server                1/1     1            1           3m11s
harbor          harbor-harbor-notary-signer                1/1     1            1           3m11s
harbor          harbor-harbor-portal                       1/1     1            1           3m11s
harbor          harbor-harbor-registry                     1/1     1            1           3m11s
```

### Создаем свой helm chart

Типичная жизненная ситуация:

- У вас есть приложение, которое готово к запуску в Kubernetes
- У вас есть манифесты для этого приложения, но вам надо запускать его на разных окружениях с разными параметрами

Возможные варианты решения:

- Написать разные манифесты для разных окружений
- Использовать "костыли" - sed, envsubst, etc...
- Использовать полноценное решение для шаблонизации (helm, etc...)

Мы рассмотрим третий вариант. Возьмем готовые манифесты и подготовим их к релизу на разные окружения.

Использовать будем демо-приложение [hipster-shop](https://github.com/GoogleCloudPlatform/microservices-demo), представляющее собой типичный набор микросервисов.

Стандартными средствами helm инициализируем структуру директории с содержимым будущего helm chart

```console
helm create kubernetes-templating/hipster-shop
```

Изучим созданный в качестве примера файл values.yaml и шаблоны в директории templates, примерно так выглядит стандартный helm chart.

Мы будем создавать chart для приложения с нуля, поэтому удалим values.yaml и содержимое templates.

После этого перенесем [файл](https://github.com/express42/otus-platform-snippets/blob/master/Module-04/05-Templating/manifests/all-hipster-shop.yaml) all-hipster-shop.yaml в директорию templates.

В целом, helm chart уже готов, попробуем установить его:

```console
kubectl create ns hipster-shop
namespace/hipster-shop created

helm upgrade --install hipster-shop kubernetes-templating/hipster-shop --namespace hipster-shop
Release "hipster-shop" does not exist. Installing it now.
NAME: hipster-shop
LAST DEPLOYED: Fri May 29 00:39:12 2020
NAMESPACE: hipster-shop
STATUS: deployed
REVISION: 1
TEST SUITE: None
```

После этого можно зайти в UI используя сервис типа NodePort (создается из манифестов) и проверить, что приложение заработало.

```console
kubectl get svc -n hipster-shop -l app=frontend
NAME       TYPE       CLUSTER-IP    EXTERNAL-IP   PORT(S)        AGE
frontend   NodePort   10.0.11.161   <none>        80:32500/TCP   12h
```

> Добавим правило FW разрешающее доступ по порту 32500 на все worker хосты GKE.

Сейчас наш helm chart **hipster-shop** совсем не похож на настоящий. При этом, все микросервисы устанавливаются из одного файла all-hipster-shop.yaml

Давайте исправим это и первым делом займемся микросервисом frontend. Скорее всего он разрабатывается отдельной командой, а исходный код хранится в отдельном репозитории.

Поэтому, было бы логично вынести все что связано с frontend в отдельный helm chart.

Создадим заготовку:

```console
helm create kubernetes-templating/frontend
```

Аналогично чарту **hipster-shop** удалим файл values.yaml и файлы в директории templates, создаваемые по умолчанию.

Выделим из файла all-hipster-shop.yaml манифесты для установки микросервиса frontend.

В директории templates чарта frontend создадим файлы:

- deployment.yaml - должен содержать соответствующую часть из файла all-hipster-shop.yaml
- service.yaml - должен содержать соответствующую часть из файла all-hipster-shop.yaml
- ingress.yaml - должен разворачивать ingress с доменным именем shop.<IP-адрес>.nip.io

После того, как вынесем описание deployment и service для **frontend** из файла all-hipster-shop.yaml переустановим chart hipster-shop и проверим, что доступ к UI пропал и таких ресурсов больше нет.

```console
helm upgrade --install hipster-shop kubernetes-templating/hipster-shop --namespace hipster-shop
Release "hipster-shop" has been upgraded. Happy Helming!
NAME: hipster-shop
LAST DEPLOYED: Fri May 29 13:33:57 2020
NAMESPACE: hipster-shop
STATUS: deployed
REVISION: 2
TEST
SUITE: None
```console

Установим chart **frontend** в namespace **hipster-shop** и проверим, что доступ к UI вновь появился:

```console
helm upgrade --install frontend kubernetes-templating/frontend --namespace hipster-shop
Release "frontend" does not exist. Installing it now.
NAME: frontend
LAST DEPLOYED: Fri May 29 13:36:06 2020
NAMESPACE: hipster-shop
STATUS: deployed
REVISION: 1
TEST SUITE: None
```

Пришло время минимально шаблонизировать наш chart **frontend**

Для начала продумаем структуру файла values.yaml

- Docker образ из которого выкатывается frontend может пересобираться, поэтому логично вынести его тег в переменную **frontend.image.tag**

В values.yaml это будет выглядеть следующим образом:

```yml
image:
  tag: v0.1.3
```

> ❗Это значение по умолчанию и может (и должно быть) быть переопределено в CI/CD pipeline

Теперь в манифесте deployment.yaml надо указать, что мы хотим использовать это переменную.

Было:

```yml
image: gcr.io/google-samples/microservices-demo/frontend:v0.1.3
```

Стало:

```yml
image: gcr.io/google-samples/microservices-demo/frontend:{{ .Values.image.tag }}
```

Аналогичным образом шаблонизируем следующие параметры **frontend** chart

- Количество реплик в deployment
- **Port**, **targetPort** и **NodePort** в service
- Опционально - тип сервиса. Ключ **NodePort** должен появиться в манифесте только если тип сервиса - **NodePort**
- Другие параметры, которые на наш взгляд стоит шаблонизировать

> ❗Не забываем указывать в файле values.yaml значения по умолчанию

Как должен выглядеть минимальный итоговый файл values.yaml:

```yml
image:
  tag: v0.1.3

replicas: 1

service:
  type: NodePort
  port: 80
  targetPort: 8080
  NodePort: 32500
```

service.yaml:

```yml
spec:
  type: {{ .Values.service.type }}
  selector:
    app: frontend
  ports:
  - name: http
    port: {{ .Values.service.port }}
    targetPort: {{ .Values.service.targetPort }}
    nodePort: {{ .Values.service.NodePort }}
```

Теперь наш **frontend** стал немного похож на настоящий helm chart. Не стоит забывать, что он все еще является частью одного
большого микросервисного приложения **hipster-shop**.

Поэтому было бы неплохо включить его в зависимости этого приложения.

Для начала, удалим release frontend из кластера:

```console
helm delete frontend -n hipster-shop
release "frontend" uninstalled
```

В Helm 2 файл requirements.yaml содержал список зависимостей helm chart (другие chart).  
В Helm 3 список зависимостей рекомендуют объявлять в файле Chart.yaml.

> При указании зависимостей в старом формате, все будет работать, единственное выдаст предупреждение. [Подробнее](https://helm.sh/docs/faq/#consolidation-of-requirements-yaml-into-chart-yaml)

Добавим chart **frontend** как зависимость

```yml
dependencies:
  - name: frontend
    version: 0.1.0
    repository: "file://../frontend"
```

Обновим зависимости:

```console
helm dep update kubernetes-templating/hipster-shop
Hang tight while we grab the latest from your chart repositories...
...Successfully got an update from the "harbor" chart repository
...Successfully got an update from the "jetstack" chart repository
...Successfully got an update from the "stable" chart repository
Update Complete. ⎈Happy Helming!⎈
Saving 1 charts
Deleting outdated charts
```

В директории kubernetes-templating/hipster-shop/charts появился архив **frontend-0.1.0.tgz** содержащий chart frontend определенной версии и добавленный в chart hipster-shop как зависимость.

Обновим release **hipster-shop** и убедимся, что ресурсы frontend вновь созданы.

```console
helm upgrade --install hipster-shop kubernetes-templating/hipster-shop --namespace hipster-shop
Release "hipster-shop" has been upgraded. Happy Helming!
NAME: hipster-shop
LAST DEPLOYED: Fri May 29 14:36:18 2020
NAMESPACE: hipster-shop
STATUS: deployed
REVISION: 3
TEST SUITE: None
```

Осталось понять, как из CI-системы мы можем менять параметры helm chart, описанные в values.yaml.

Для этого существует специальный ключ **--set**

Изменим NodePort для **frontend** в release, не меняя его в самом chart:

```console
helm upgrade --install hipster-shop kubernetes-templating/hipster-shop --namespace hipster-shop --set frontend.service.NodePort=31234
```

> Так как как мы меняем значение переменной для зависимости - перед названием переменной указываем имя (название chart) этой зависимости.  
> Если бы мы устанавливали chart frontend напрямую, то команда выглядела бы как --set service.NodePort=31234

```console
helm upgrade --install hipster-shop kubernetes-templating/hipster-shop --namespace hipster-shop --set frontend.service.NodePort=31234
Release "hipster-shop" has been upgraded. Happy Helming!
NAME: hipster-shop
LAST DEPLOYED: Fri May 29 15:39:44 2020
NAMESPACE: hipster-shop
STATUS: deployed
REVISION: 4
TEST SUITE: None
```

### Создаем свой helm chart | Задание со ⭐

Выберем сервис, который можно установить как зависимость, используя community chart's. Например, это может быть **Redis**.

- Удалим из all-hipster-shop.yaml часть манифеста касательно redis
- Добавим repo с redis

```console
helm repo add bitnami https://charts.bitnami.com/bitnami
"bitnami" has been added to your repositories
```

- дополняем наш Charts.yaml

```yml
dependencies:
  - name: redis
    version: 10.6.17
    repository: https://charts.bitnami.com/bitnami
```

- меняем значение переменной окружения **REDIS_ADDR** с redis-cart на redis-cart-master для cartservice Deployment
- обновляем dep для hipster-shop: helm dep update kubernetes-templating/hipster-shop
- выкатываем:

```console
helm upgrade --install hipster-shop kubernetes-templating/hipster-shop --namespace hipster-shop
Release "hipster-shop" has been upgraded. Happy Helming!
NAME: hipster-shop
LAST DEPLOYED: Fri May 29 16:20:22 2020
NAMESPACE: hipster-shop
STATUS: deployed
REVISION: 5
TEST SUITE: None
```

- Проверяем создание pod

```console
kubectl get pods -n hipster-shop

NAME                                     READY   STATUS    RESTARTS   AGE
adservice-55f9757757-jnr72               1/1     Running   0          3h37m
cartservice-78577c6fbf-ldm7k             1/1     Running   15         88m
checkoutservice-6fcc84467f-27wrn         1/1     Running   0          3h37m
currencyservice-8b7b8c647-mqsmj          1/1     Running   0          3h37m
emailservice-6c46854ccc-bxxsv            1/1     Running   0          3h37m
frontend-745f64f8b6-rfmvx                1/1     Running   0          3h18m
paymentservice-76654769f7-xvlg8          1/1     Running   0          3h37m
productcatalogservice-d564bdf4c-2cr74    1/1     Running   0          3h37m
recommendationservice-76598d5889-jsq6m   1/1     Running   0          3h37m
redis-cart-master-0                      1/1     Running   0          1m
shippingservice-b6db65f7f-qshbv          1/1     Running   0          3h37m
```

- Проверяем что UI работает

### Работа с helm-secrets | Необязательное задание

Разберемся как работает плагин **helm-secrets**. Для этого добавим в Helm chart секрет и научимся хранить его в зашифрованном виде.

Начнем с того, что установим плагин и необходимые для него зависимости (здесь и далее инструкции приведены для MacOS):

```console
brew install sops
brew install gnupg2
brew install gnu-getopt
helm plugin install https://github.com/futuresimple/helm-secrets --version 2.0.2
sops is already installed:
sops 3.5.0 (latest)
Installed plugin: secrets
```

> В домашней работы мы будем использовать PGP, но также можно воспользоваться KMS.

Сгенерируем новый PGP ключ:

```console
gpg --full-generate-key
```

После этого командой gpg -k можно проверить, что ключ появился:

```console
gpg -k
gpg: проверка таблицы доверия
gpg: marginals needed: 3  completes needed: 1  trust model: pgp
gpg: глубина: 0  достоверных:   1  подписанных:   0  доверие: 0-, 0q, 0n, 0m, 0f, 1u
/Users/alexey/.gnupg/pubring.kbx
--------------------------------
pub   rsa2048 2020-05-29 [SC]
      1EFA58CC515C2A87D5834A86C12D0C3E96B08842
uid         [  абсолютно ] alexey <kovtalex@hmail.com>
sub   rsa2048 2020-05-29 [E]
```

Создадим новый файл secrets.yaml в директории kubernetestemplating/frontend со следующим содержимым:

```yml
visibleKey: hiddenValue
```

И попробуем зашифровать его: sops -e -i --pgp <$ID> secrets.yaml

> Примечание - вместо ID подставим длинный хеш, в выводе на предыдущей странице это 1EFA58CC515C2A87D5834A86C12D0C3E96B08842

```console
sops -e -i --pgp 1EFA58CC515C2A87D5834A86C12D0C3E96B08842 kubernetes-templating/frontend/secrets.yaml
```

Проверим, что файл secrets.yaml изменился. Сейчас его содержание должно выглядеть примерно так:

```yml
visibleKey: ENC[AES256_GCM,data:fOgyl1H2cmc5kYo=,iv:Cv54qLIkjV1/S3MEyyMPlBmBUp3sIER+Fw8duXgRpR8=,tag:A01Z0Vlrtncn3sTk4JyCtQ==,type:str]
sops:
    kms: []
    gcp_kms: []
    azure_kv: []
    lastmodified: '2020-05-29T15:44:09Z'
    mac: ENC[AES256_GCM,data:rPXR9oZwlZ0eayWmXa47lBAnpsVjijkFikLX1xs42+sprwyu3Iq2UgP5rstYNNwE6J0ZzjRivQXRoCTM+Y2GI6JkZTO6B95E9xfBblFlqjb1L+63btovUnI6z+IyMCl+eAZO6dK7jYgGu21T6PfS3pk2RrdYSJ6tDIkZOqlZMIw=,iv:nnNKQ0cfGR+0FCsXv/CtFli628WZjNq8sn6Hv9uni/0=,tag:324Mv9MZxIMyLycZZsDALQ==,type:str]
    pgp:
    -   created_at: '2020-05-29T15:44:05Z'
        enc: |
            -----BEGIN PGP MESSAGE-----

            hQEMA+tUwpJ4avm2AQf/fnDnm99OZrxgtmyeSE1KsHH4/ux0NLbmffT4yjKMg+yW
            rwAhueBVt/utNCFyVSH6BAcMFP9Wy3EYvbKzZJx9/ypjXaJ+aZZ7MSzKRnNgauF3
            pSB9noScMWquShGubvgsXr++Jc7aXd/qSCrIbrgkDfHTSYri4QO9CjkmZIXXFXdJ
            ijx+BpgsJtWsCM/pzBMi31q0AU4G0SulH5CsVeg5TvrZMuUPzihVrqD4yOxZU3xx
            w+QHtiDHzXxYowQTV9UVBiwaBEf1+pl2CYY3E5gizn7CuQuRc1bttvuGdht34YDH
            TjRRmoFs0hPGEJFzbGfUMe8j8pb8ZApD2y5YZpzmSNJcAWumbdpN5agLapOCs0AJ
            iZOW83tRSg4C6uc/eSZ9Z+IsoAq9fYDXrWVitXRuZ7AkTSB9J7Jm6YUrB8r39bx5
            uux6k7/6QjN9OlZIbHIZHA7aPzmAZVPNDws2e9Q=
            =742r
            -----END PGP MESSAGE-----
        fp: 1EFA58CC515C2A87D5834A86C12D0C3E96B08842
    unencrypted_suffix: _unencrypted
    version: 3.5.0
```

> Заметим, что структура файла осталась прежней. Мы видим ключ visibleKey, но его значение зашифровано

В таком виде файл уже можно коммитить в Git, но для начала - научимся расшифровывать его.

Можно использовать любой из инструментов:

```console
# helm secrets
helm secrets view secrets.yaml

# sops
sops -d secrets.yaml
```

```console
helm secrets view kubernetes-templating/frontend/secrets.yaml
visibleKey: hiddenValue
```

```console
sops -d kubernetes-templating/frontend/secrets.yaml
visibleKey: hiddenValue
```

Теперь осталось понять, как добавить значение нашего секрета в настоящий секрет kubernetes и устанавливать его вместе с основным helm chart.

Создадим в директории kubernetestemplating/frontend/templates еще один файл secret.yaml.  
Несмотря на похожее название его предназначение будет отличаться.

Поместим туда следующий шаблон:

```yml
apiVersion: v1
kind: Secret
metadata:
  name: secret
type: Opaque
data:
  visibleKey: {{ .Values.visibleKey | b64enc | quote }}
```

Теперь, если мы передадим в helm файл secrets.yaml как values файл - плагин **helm-secrets** поймет, что его надо расшифровать, а значение ключа visibleKey подставить в соответствующий шаблон секрета.

Запустим установку:

```console
helm secrets upgrade --install frontend kubernetes-templating/frontend --namespace hipster-shop \
-f kubernetes-templating/frontend/values.yaml \
-f kubernetes-templating/frontend/secrets.yaml

Release "frontend" does not exist. Installing it now.
NAME: frontend
LAST DEPLOYED: Fri May 29 18:50:00 2020
NAMESPACE: hipster-shop
STATUS: deployed
REVISION: 1
TEST SUITE: None
kubernetes-templating/frontend/secrets.yaml.dec
```

> В процессе установки **helm-secrets** расшифрует наш секретный файл в другой временный файл secrets.yaml.dec, а после выполнения установки - удалит его

- Проверим, что секрет создан и его содержимое соответсвуем нашим ожиданиям

```console
kubectl get secrets secret -n hipster-shop -o yaml
apiVersion: v1
data:
  visibleKey: aGlkZGVuVmFsdWU=
kind: Secret
metadata:
  annotations:
    meta.helm.sh/release-name: frontend
    meta.helm.sh/release-namespace: hipster-shop
  creationTimestamp: "2020-05-29T15:50:00Z"
  labels:
    app.kubernetes.io/managed-by: Helm
  name: secret
  namespace: hipster-shop
  resourceVersion: "811436"
  selfLink: /api/v1/namespaces/hipster-shop/secrets/secret
  uid: b22f6a8d-6c8e-49a7-bcc2-3b86ce59a8ce
type: Opaque
```

```console
kubectl get secrets secret -n hipster-shop -o "jsonpath={.data.visibleKey}" | base64 -D
hiddenValue%
```

- В CI/CD плагин helm-secrets можно использовать для подготовки авторизации на различных сервисах
- Как обезопасить себя от коммита файлов с секретами - <https://github.com/zendesk/helm-secrets#important-tips>

### Проверка

Поместим все получившиеся helm chart's в наш установленный harbor в публичный проект.

Установим helm-push

```console
helm plugin install https://github.com/chartmuseum/helm-push.git
```

Создадим файл kubernetes-templating/repo.sh со следующим содержанием:

```bash
#!/bin/bash
helm repo add templating https://harbor.35.189.202.237.nip.io/chartrepo/library

helm push --username admin --password Harbor12345  frontend/ templating
helm push --username admin --password Harbor12345  hipster-shop/ templating
```

```console
./repo.sh
"templating" has been added to your repositories
Pushing frontend-0.1.0.tgz to templating...
Done.
Pushing hipster-shop-0.1.0.tgz to templating...
Done.
```

Проверим:

Представим, что одна из команд разрабатывающих сразу несколько микросервисов нашего продукта решила, что helm не подходит для ее нужд и попробовала использовать решение на основе **jsonnet - kubecfg**.

Посмотрим на возможности этой утилиты. Работать будем с сервисами paymentservice и shippingservice. Для начала - вынесем манифесты описывающие **service** и **deployment** для этих микросервисов из файла all-hipstershop.yaml в директорию kubernetes-templating/kubecfg

Проверим:

```console
helm search repo -l templating
NAME                    CHART VERSION   APP VERSION     DESCRIPTION
templating/frontend     0.1.0           1.16.0          A Helm chart for Kubernetes
templating/hipster-shop 0.1.0           1.16.0          A Helm chart for Kubernetes
```

И развернем:

```console
helm upgrade --install hipster-shop templating/hipster-shop --namespace hipster-shop
helm upgrade --install frontend templating/frontend --namespace hipster-shop
```

### Kubecfg

Представим, что одна из команд разрабатывающих сразу несколько микросервисов нашего продукта решила, что helm не подходит для ее нужд и попробовала использовать решение на основе **jsonnet - kubecfg**.

Посмотрим на возможности этой утилиты. Работать будем с сервисами paymentservice и shippingservice.

Для начала - вынесем манифесты описывающие **service** и **deployment** для этих микросервисов из файла all-hipstershop.yaml в директорию kubernetes-templating/kubecfg

В итоге должно получиться четыре файла:

```console
tree -L 1 kubecfg
kubecfg
├── paymentservice-deployment.yaml
├── paymentservice-service.yaml
├── shippingservice-deployment.yaml
└── shippingservice-service.yaml
```

Можно заметить, что манифесты двух микросервисов очень похожи друг на друга и может иметь смысл генерировать их из какого-то шаблона.  
Попробуем сделать это.

Обновим release hipster-shop, проверим, что микросервисы paymentservice и shippingservice исчезли из установки и магазин стал работать некорректно (при нажатии на кнопку Add to Cart).

```console
helm upgrade --install hipster-shop kubernetes-templating/hipster-shop --namespace hipster-shopRelease "hipster-shop" has been upgraded. Happy Helming!
NAME: hipster-shop
LAST DEPLOYED: Fri May 29 23:26:43 2020
NAMESPACE: hipster-shop
STATUS: deployed
REVISION: 2
TEST SUITE: None
```

Установим [kubecfg](https://github.com/bitnami/kubecfg) (доступна в виде сборок по MacOS и Linux и в Homebrew)

```console
brew install kubecfg

kubecfg version
kubecfg version: v0.16.0
jsonnet version: v0.15.0
client-go version: v0.0.0-master+604c38a2
```

Kubecfg предполагает хранение манифестов в файлах формата .jsonnet и их генерацию перед установкой. Пример такого файла
можно найти в [официальном репозитории](https://github.com/bitnami/kubecfg/blob/master/examples/guestbook.jsonnet)

Напишем по аналогии свой .jsonnet файл - services.jsonnet.

Для начала в файле мы должны указать libsonnet библиотеку, которую будем использовать для генерации манифестов. В домашней работе воспользуемся [готовой от bitnami](https://github.com/bitnami-labs/kube-libsonnet/)

```console
wget https://github.com/bitnami-labs/kube-libsonnet/raw/52ba963ca44f7a4960aeae9ee0fbee44726e481f/kube.libsonnet
```

> ❗ В kube.libsonnet исправим версию api для Deploymens и Service на apps/v1

Импортируем ее:

```json
local kube = import "kube.libsonnet";
```

Перейдем к основной части

Общая логика происходящего следующая:

1. Пишем общий для сервисов [шаблон](https://raw.githubusercontent.com/express42/otus-platform-snippets/master/Module-04/05-Templating/hipster-shop-jsonnet/common.jsonnet), включающий описание service и deployment
2. [Наследуемся](https://raw.githubusercontent.com/express42/otus-platform-snippets/master/Module-04/05-Templating/hipster-shop-jsonnet/payment-shipping.jsonnet) от него, указывая параметры для конкретных

services.jsonnet:

```json
local kube = import "kube.libsonnet";

local common(name) = {

  service: kube.Service(name) {
    target_pod:: $.deployment.spec.template,
  },

  deployment: kube.Deployment(name) {
    spec+: {
      template+: {
        spec+: {
          containers_: {
            common: kube.Container("common") {
              env: [{name: "PORT", value: "50051"}],
              ports: [{containerPort: 50051}],
              securityContext: {
                readOnlyRootFilesystem: true,
                runAsNonRoot: true,
                runAsUser: 10001,
              },
              readinessProbe: {
                  initialDelaySeconds: 20,
                  periodSeconds: 15,
                  exec: {
                      command: [
                          "/bin/grpc_health_probe",
                          "-addr=:50051",
                      ],
                  },
              },
              livenessProbe: {
                  initialDelaySeconds: 20,
                  periodSeconds: 15,
                  exec: {
                      command: [
                          "/bin/grpc_health_probe",
                          "-addr=:50051",
                      ],
                  },
              },
            },
          },
        },
      },
    },
  },
};


{
  catalogue: common("paymentservice") {
    deployment+: {
      spec+: {
        template+: {
          spec+: {
            containers_+: {
              common+: {
                name: "server",
                image: "gcr.io/google-samples/microservices-demo/paymentservice:v0.1.3",
              },
            },
          },
        },
      },
    },
  },

  payment: common("shippingservice") {
    deployment+: {
      spec+: {
        template+: {
          spec+: {
            containers_+: {
              common+: {
                name: "server",
                image: "gcr.io/google-samples/microservices-demo/shippingservice:v0.1.3",
              },
            },
          },
        },
      },
    },
  },
}
```

Проверим, что манифесты генерируются корректно:

```console
kubecfg show services.jsonnet
---
apiVersion: apps/v1
kind: Deployment
metadata:
  annotations: {}
  labels:
    name: paymentservice
  name: paymentservice
spec:
  minReadySeconds: 30
  replicas: 1
  selector:
    matchLabels:
      name: paymentservice
  strategy:
    rollingUpdate:
      maxSurge: 25%
      maxUnavailable: 25%
    type: RollingUpdate
  template:
    metadata:
      annotations: {}
      labels:
        name: paymentservice
    spec:
      containers:
      - args: []
        env:
        - name: PORT
          value: "50051"
        image: gcr.io/google-samples/microservices-demo/paymentservice:v0.1.3
        imagePullPolicy: IfNotPresent
        livenessProbe:
          exec:
            command:
            - /bin/grpc_health_probe
            - -addr=:50051
          initialDelaySeconds: 20
          periodSeconds: 15
        name: server
        ports:
        - containerPort: 50051
        readinessProbe:
          exec:
            command:
            - /bin/grpc_health_probe
            - -addr=:50051
          initialDelaySeconds: 20
          periodSeconds: 15
        securityContext:
          readOnlyRootFilesystem: true
          runAsNonRoot: true
          runAsUser: 10001
        stdin: false
        tty: false
        volumeMounts: []
      imagePullSecrets: []
      initContainers: []
      terminationGracePeriodSeconds: 30
      volumes: []
---
apiVersion: v1
kind: Service
metadata:
  annotations: {}
  labels:
    name: paymentservice
  name: paymentservice
spec:
  ports:
  - port: 50051
    targetPort: 50051
  selector:
    name: paymentservice
  type: ClusterIP
---
apiVersion: apps/v1
kind: Deployment
metadata:
  annotations: {}
  labels:
    name: shippingservice
  name: shippingservice
spec:
  minReadySeconds: 30
  replicas: 1
  selector:
    matchLabels:
      name: shippingservice
  strategy:
    rollingUpdate:
      maxSurge: 25%
      maxUnavailable: 25%
    type: RollingUpdate
  template:
    metadata:
      annotations: {}
      labels:
        name: shippingservice
    spec:
      containers:
      - args: []
        env:
        - name: PORT
          value: "50051"
        image: gcr.io/google-samples/microservices-demo/shippingservice:v0.1.3
        imagePullPolicy: IfNotPresent
        livenessProbe:
          exec:
            command:
            - /bin/grpc_health_probe
            - -addr=:50051
          initialDelaySeconds: 20
          periodSeconds: 15
        name: server
        ports:
        - containerPort: 50051
        readinessProbe:
          exec:
            command:
            - /bin/grpc_health_probe
            - -addr=:50051
          initialDelaySeconds: 20
          periodSeconds: 15
        securityContext:
          readOnlyRootFilesystem: true
          runAsNonRoot: true
          runAsUser: 10001
        stdin: false
        tty: false
        volumeMounts: []
      imagePullSecrets: []
      initContainers: []
      terminationGracePeriodSeconds: 30
      volumes: []
---
apiVersion: v1
kind: Service
metadata:
  annotations: {}
  labels:
    name: shippingservice
  name: shippingservice
spec:
  ports:
  - port: 50051
    targetPort: 50051
  selector:
    name: shippingservice
  type: ClusterIP
```

И установим их:

```console
kubecfg update services.jsonnet --namespace hipster-shop
INFO  Validating deployments paymentservice
INFO  validate object "apps/v1, Kind=Deployment"
INFO  Validating services paymentservice
INFO  validate object "/v1, Kind=Service"
INFO  Validating services shippingservice
INFO  validate object "/v1, Kind=Service"
INFO  Validating deployments shippingservice
INFO  validate object "apps/v1, Kind=Deployment"
INFO  Fetching schemas for 4 resources
INFO  Creating services paymentservice
INFO  Creating services shippingservice
INFO  Creating deployments paymentservice
INFO  Creating deployments shippingservice
```

Через какое-то время магазин снова должен заработать и товары можно добавить в корзину

### Задание со ⭐ | qbec

Выберем еще один микросервис (recommendationservice)из состава hipster-shop и попробуем использовать другое решение на основе jsonnet,
например [qbec](https://github.com/splunk/qbec)

Также можно использовать [Kapitan](https://github.com/deepmind/kapitan)

Приложим артефакты их использования в директорию kubernetes-templating/jsonnet и опишем проделанную работу и порядок установки.

- Установим qbec

```console
brew tap splunk/tap
brew install qbec
```

- Подготовим новую структуру для приложения

```console
qbec init recommendationservice
using server URL "https://34.78.75.22" and default namespace "default" for the default environment
wrote recommendationservice/params.libsonnet
wrote recommendationservice/environments/base.libsonnet
wrote recommendationservice/environments/default.libsonnet
wrote recommendationservice/qbec.yaml
```

- Конвертируем манифест Deployment и Service (recommendationservice) из yaml в json и поместим результат в компонент components/recommendationservice.jsonnet
- Также добавим в components/recommendationservice.jsonnet блок:

```json
local env = {
  name: std.extVar('qbec.io/env'),
  namespace: std.extVar('qbec.io/defaultNs'),
};
local p = import '../params.libsonnet';
local params = p.components.recommendationservice;
```

- Шаблонизируем необходимые нам параметры в components/recommendationservice.jsonnet:

```json
            "resources": {
              "requests": {
                "cpu": params.cpu_requests,
                "memory": params.memory_requests
              },
              "limits": {
                "cpu": params.cpu_limits,
                "memory": params.memory_limits
              }
            }
```

- Определим их значения по умолчанию для всех окружений в environments/base.libsonnet:

```json
{
  components: {
    recommendationservice: {
      name: "recommendationservice",
      image: "gcr.io/google-samples/microservices-demo/recommendationservice:v0.1.3",
      replicas: 1,

      cpu_requests: "100m",
      memory_requests: "220Mi",
      cpu_limits: "200m",
      memory_limits: "450Mi",

      containterPort: 8080,
      servicePort: 8080,
    },
  },
}
```

- Создадим environments/dev.libsonnet содержаший значения переменных для окружение dev:

```json
local base = import './base.libsonnet';

base {
  components +: {
      recommendationservice +: {
          name: "dev-recommendationservice",
          replicas: 3,
      },
  },
}
```

- Добавим наше новое окружение dev в params.libsonnet:

```json
  dev: import './environments/dev.libsonnet',
```

- И в qbec.yaml:

```json
    dev:
      defaultNamespace: hipster-shop
      server: https://34.78.75.22
  namespaceTagSuffix: true
```

> namespaceTagSuffix: true - позволит добавлять суффикс к namespace, указывая в командной строке: --app-tag=\<suffix\>

- Провалидируем окружение по умолчанию

```console
qbec validate default
setting cluster to gke_angular-pursuit-275120_europe-west1-b_cluster-1
setting context to gke_angular-pursuit-275120_europe-west1-b_cluster-1
cluster metadata load took 334ms
1 components evaluated in 4ms
✔ deployments recommendationservice -n hipster-shop (source recommendationservice) is valid
✔ services recommendationservice -n hipster-shop (source recommendationservice) is valid
---
stats:
  valid: 2

command took 540ms
```

- Просмотрим:

```yml
qbec show default
1 components evaluated in 5ms
---
apiVersion: apps/v1
kind: Deployment
metadata:
  annotations:
    qbec.io/component: recommendationservice
  labels:
    qbec.io/application: recommendationservice
    qbec.io/environment: default
  name: recommendationservice
spec:
  replicas: 1
  selector:
    matchLabels:
      app: recommendationservice
  template:
    metadata:
      labels:
        app: recommendationservice
    spec:
      containers:
      - env:
        - name: PORT
          value: "8080"
        - name: PRODUCT_CATALOG_SERVICE_ADDR
          value: productcatalogservice:3550
        - name: ENABLE_PROFILER
          value: "0"
        image: gcr.io/google-samples/microservices-demo/recommendationservice:v0.1.3
        livenessProbe:
          exec:
            command:
            - /bin/grpc_health_probe
            - -addr=:8080
          periodSeconds: 5
        name: server
        ports:
        - containerPort: 8080
        readinessProbe:
          exec:
            command:
            - /bin/grpc_health_probe
            - -addr=:8080
          periodSeconds: 5
        resources:
          limits:
            cpu: 200m
            memory: 450Mi
          requests:
            cpu: 100m
            memory: 220Mi
      terminationGracePeriodSeconds: 5

---
apiVersion: v1
kind: Service
metadata:
  annotations:
    qbec.io/component: recommendationservice
  labels:
    qbec.io/application: recommendationservice
    qbec.io/environment: default
  name: recommendationservice
spec:
  ports:
  - name: grpc
    port: 8080
    targetPort: 8080
  selector:
    app: recommendationservice
  type: ClusterIP
```

- И выкатим:

```console
qbec apply default
setting cluster to gke_angular-pursuit-275120_europe-west1-b_cluster-1
setting context to gke_angular-pursuit-275120_europe-west1-b_cluster-1
cluster metadata load took 279ms
1 components evaluated in 2ms

will synchronize 2 object(s)

Do you want to continue [y/n]: y
1 components evaluated in 1ms
create deployments recommendationservice -n hipster-shop (source recommendationservice)
create services recommendationservice -n hipster-shop (source recommendationservice)
waiting for deletion list to be returned
server objects load took 669ms
---
stats:
  created:
  - deployments recommendationservice -n hipster-shop (source recommendationservice)
  - services recommendationservice -n hipster-shop (source recommendationservice)

command took 9.51s
```

- Проверяем

```console
kubectl get deployments -n hipster-shop
NAME                    READY   UP-TO-DATE   AVAILABLE   AGE
adservice               1/1     1            1           83m
cartservice             1/1     1            1           57m
checkoutservice         1/1     1            1           83m
currencyservice         1/1     1            1           83m
emailservice            1/1     1            1           83m
frontend                1/1     1            1           83m
paymentservice          1/1     1            1           82m
productcatalogservice   1/1     1            1           83m
recommendationservice   1/1     1            1           2m30s
shippingservice         1/1     1            1           82m
```

- Валидания для dev окружения

```console
qbec validate dev
setting cluster to gke_angular-pursuit-275120_europe-west1-b_cluster-1
setting context to gke_angular-pursuit-275120_europe-west1-b_cluster-1
cluster metadata load took 263ms
1 components evaluated in 5ms
✔ deployments dev-recommendationservice -n hipster-shop (source recommendationservice) is valid
✔ services dev-recommendationservice -n hipster-shop (source recommendationservice) is valid
---
stats:
  valid: 2

command took 500ms
```

- Просмотрим:

```yml
qbec show dev --app-tag dev
1 components evaluated in 3ms
---
apiVersion: apps/v1
kind: Deployment
metadata:
  annotations:
    qbec.io/component: recommendationservice
  labels:
    qbec.io/application: recommendationservice
    qbec.io/environment: dev
    qbec.io/tag: dev
  name: dev-recommendationservice
spec:
  replicas: 3
  selector:
    matchLabels:
      app: dev-recommendationservice
  template:
    metadata:
      labels:
        app: dev-recommendationservice
    spec:
      containers:
      - env:
        - name: PORT
          value: "8080"
        - name: PRODUCT_CATALOG_SERVICE_ADDR
          value: productcatalogservice:3550
        - name: ENABLE_PROFILER
          value: "0"
        image: gcr.io/google-samples/microservices-demo/recommendationservice:v0.1.3
        livenessProbe:
          exec:
            command:
            - /bin/grpc_health_probe
            - -addr=:8080
          periodSeconds: 5
        name: server
        ports:
        - containerPort: 8080
        readinessProbe:
          exec:
            command:
            - /bin/grpc_health_probe
            - -addr=:8080
          periodSeconds: 5
        resources:
          limits:
            cpu: 200m
            memory: 450Mi
          requests:
            cpu: 100m
            memory: 220Mi
      terminationGracePeriodSeconds: 5

---
apiVersion: v1
kind: Service
metadata:
  annotations:
    qbec.io/component: recommendationservice
  labels:
    qbec.io/application: recommendationservice
    qbec.io/environment: dev
    qbec.io/tag: dev
  name: dev-recommendationservice
spec:
  ports:
  - name: grpc
    port: 8080
    targetPort: 8080
  selector:
    app: dev-recommendationservice
  type: ClusterIP
```

> Увеличилость количество реплик и изменились значения для name

- Выкатим с dry-run

```console
qbec apply dev --app-tag dev --dry-run

---
stats:
  created:
  - deployments dev-recommendationservice -n hipster-shop-dev (source recommendationservice)
  - services dev-recommendationservice -n hipster-shop-dev (source recommendationservice)
```

- И наконец выкатим dev в namespace hipster-shop-dev

```console
qbec apply dev --app-tag dev

setting cluster to gke_angular-pursuit-275120_europe-west1-b_cluster-1
setting context to gke_angular-pursuit-275120_europe-west1-b_cluster-1
cluster metadata load took 264ms
1 components evaluated in 4ms

will synchronize 2 object(s)

Do you want to continue [y/n]: y
1 components evaluated in 2ms
create deployments dev-recommendationservice -n hipster-shop-dev (source recommendationservice)
create services dev-recommendationservice -n hipster-shop-dev (source recommendationservice)
waiting for deletion list to be returned
server objects load took 856ms
---
stats:
  created:
  - deployments dev-recommendationservice -n hipster-shop-dev (source recommendationservice)
  - services dev-recommendationservice -n hipster-shop-dev (source recommendationservice)

command took 3.07s
```

Проверяем:

```console
kubectl describe deployments -n hipster-shop-dev | grep replicas

NewReplicaSet:   dev-recommendationservice-6b6bd45b99 (3/3 replicas created)
```

### Kustomize

Отпилим еще один (cartservice) микросервис из all-hipstershop.yaml.yaml и займемся его kustomизацией.

В минимальном варианте реализуем установку на три окружения - hipster-shop (namespace hipster-shop), hipster-shop-prod (namespace hipster-shop-prod) и hipster-shop-dev (namespace hipster-shop-dev) из одних манифестов deployment и service.

Окружения должны отличаться:

- Набором labels во всех манифестах
- Префиксом названий ресурсов
- Для dev окружения значением переменной окружения REDIS_ADDR

Установим kustomize:

```console
brew install kustomize
```

Для namespace hipster-shop:

```yml
kustomize build .

apiVersion: v1
kind: Service
metadata:
  name: cartservice
  namespace: hipster-shop
spec:
  ports:
  - name: grpc
    port: 7070
    targetPort: 7070
  selector:
    app: cartservice
  type: ClusterIP
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: cartservice
  namespace: hipster-shop
spec:
  selector:
    matchLabels:
      app: cartservice
  template:
    metadata:
      labels:
        app: cartservice
    spec:
      containers:
      - env:
        - name: REDIS_ADDR
          value: redis-cart-master:6379
        - name: PORT
          value: "7070"
        - name: LISTEN_ADDR
          value: 0.0.0.0
        image: gcr.io/google-samples/microservices-demo/cartservice:v0.1.3
        livenessProbe:
          exec:
            command:
            - /bin/grpc_health_probe
            - -addr=:7070
            - -rpc-timeout=5s
          initialDelaySeconds: 15
          periodSeconds: 10
        name: server
        ports:
        - containerPort: 7070
        readinessProbe:
          exec:
            command:
            - /bin/grpc_health_probe
            - -addr=:7070
            - -rpc-timeout=5s
          initialDelaySeconds: 15
        resources:
          limits:
            cpu: 300m
            memory: 128Mi
          requests:
            cpu: 200m
            memory: 64Mi
```

Для namespace hipster-shop-dev:

```yml
kustomize build .
apiVersion: v1
kind: Service
metadata:
  labels:
    environment: dev
  name: dev-cartservice
  namespace: hipster-shop-dev
spec:
  ports:
  - name: grpc
    port: 7070
    targetPort: 7070
  selector:
    app: cartservice
    environment: dev
  type: ClusterIP
---
apiVersion: apps/v1
kind: Deployment
metadata:
  labels:
    environment: dev
  name: dev-cartservice
  namespace: hipster-shop-dev
spec:
  selector:
    matchLabels:
      app: cartservice
      environment: dev
  template:
    metadata:
      labels:
        app: cartservice
        environment: dev
    spec:
      containers:
      - env:
        - name: REDIS_ADDR
          value: redis-cart:6379
        - name: PORT
          value: "7070"
        - name: LISTEN_ADDR
          value: 0.0.0.0
        image: gcr.io/google-samples/microservices-demo/cartservice:v0.1.3
        livenessProbe:
          exec:
            command:
            - /bin/grpc_health_probe
            - -addr=:7070
            - -rpc-timeout=5s
          initialDelaySeconds: 15
          periodSeconds: 10
        name: server
        ports:
        - containerPort: 7070
        readinessProbe:
          exec:
            command:
            - /bin/grpc_health_probe
            - -addr=:7070
            - -rpc-timeout=5s
          initialDelaySeconds: 15
        resources:
          limits:
            cpu: 300m
            memory: 128Mi
          requests:
            cpu: 200m
            memory: 64Mi
```

Задеплоим и проверим работу UI:

```console
kustomize build . | kubectl apply -f -

Warning: kubectl apply should be used on resource created by either kubectl create --save-config or kubectl apply
service/cartservice created
deployment.apps/cartservice created
```

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

minio-headless-service.yaml

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

kubectl apply -f minio-headless-service.yaml
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

### Задание со ⭐

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

Изменим minio-headless-service.yaml для использования нашего Secret:

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
