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