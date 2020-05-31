local base = import './base.libsonnet';

base {
  components +: {
      recommendationservice +: {
          name: "dev-recommendationservice",
          replicas: 3,
      },
  }
}
