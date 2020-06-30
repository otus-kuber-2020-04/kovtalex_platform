USERNAME=kovtalex
APP_TAG=v0.0.1

.PHONY: build release

# Build

build: build_adservice build_checkoutservice build_emailservice build_loadgenerator build_productcatalogservice build_shippingservice build_cartservice build_currencyservice build_frontend build_paymentservice build_recommendationservice

build_adservice:
	export USER_NAME=$(USERNAME) && cd microservices-demo/src/adservice && docker build -t kovtalex/adservice:$(APP_TAG) .

build_cartservice:
	export USER_NAME=$(USERNAME) && cd microservices-demo/src/cartservice && docker build -t kovtalex/cartservice:$(APP_TAG) .

build_checkoutservice:
	export USER_NAME=$(USERNAME) && cd microservices-demo/src/checkoutservice && docker build -t kovtalex/checkoutservice:$(APP_TAG) .

build_currencyservice:
	export USER_NAME=$(USERNAME) && cd microservices-demo/src/currencyservice && docker build -t kovtalex/currencyservice:$(APP_TAG) .

build_emailservice:
	export USER_NAME=$(USERNAME) && cd microservices-demo/src/emailservice && docker build -t kovtalex/emailservice:$(APP_TAG) .

build_frontend:
	export USER_NAME=$(USERNAME) && cd microservices-demo/src/frontend && docker build -t kovtalex/frontend:$(APP_TAG) .

build_loadgenerator:
	export USER_NAME=$(USERNAME) && cd microservices-demo/src/loadgenerator && docker build -t kovtalex/loadgenerator:$(APP_TAG) .

build_paymentservice:
	export USER_NAME=$(USERNAME) && cd microservices-demo/src/paymentservice && docker build -t kovtalex/paymentservice:$(APP_TAG) .

build_productcatalogservice:
	export USER_NAME=$(USERNAME) && cd microservices-demo/src/productcatalogservice && docker build -t kovtalex/productcatalogservice:$(APP_TAG) .

build_recommendationservice:
	export USER_NAME=$(USERNAME) && cd microservices-demo/src/recommendationservice && docker build -t kovtalex/recommendationservice:$(APP_TAG) .

build_shippingservice:
	export USER_NAME=$(USERNAME) && cd microservices-demo/src/shippingservice && docker build -t kovtalex/shippingservice:$(APP_TAG) .

# Release

release: release_adservice release_checkoutservice release_emailservice release_loadgenerator release_productcatalogservice release_shippingservice release_cartservice release_currencyservice release_frontend release_paymentservice release_recommendationservice

release_adservice:
	docker push $(USERNAME)/adservice:$(APP_TAG)

release_cartservice:
	docker push $(USERNAME)/cartservice:$(APP_TAG)

release_checkoutservice:
	docker push $(USERNAME)/checkoutservice:$(APP_TAG)

release_currencyservice:
	docker push $(USERNAME)/currencyservice:$(APP_TAG)

release_emailservice:
	docker push $(USERNAME)/emailservice:$(APP_TAG)

release_frontend:
	docker push $(USERNAME)/frontend:$(APP_TAG)

release_loadgenerator:
	docker push $(USERNAME)/loadgenerator:$(APP_TAG)

release_paymentservice:
	docker push $(USERNAME)/paymentservice:$(APP_TAG)

release_productcatalogservice:
	docker push $(USERNAME)/productcatalogservice:$(APP_TAG)

release_recommendationservice:
	docker push $(USERNAME)/recommendationservice:$(APP_TAG)

release_shippingservice:
	docker push $(USERNAME)/shippingservice:$(APP_TAG)
