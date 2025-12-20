package com.minishop.gateway;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.client.RestClient;

import java.util.HashMap;
import java.util.List;
import java.util.Map;

@RestController
public class GatewayController {

    private final RestClient productClient;
    private final RestClient orderClient;

    public GatewayController(
            @Value("${services.product.url}") String productUrl,
            @Value("${services.order.url}") String orderUrl
    ) {
        this.productClient = RestClient.builder().baseUrl(productUrl).build();
        this.orderClient = RestClient.builder().baseUrl(orderUrl).build();
    }

    @GetMapping("/api/products")
    public List<Product> products() {
        return productClient.get()
                .uri("/products")
                .retrieve()
                .body(new org.springframework.core.ParameterizedTypeReference<List<Product>>() {});
    }

    @GetMapping("/api/orders")
    public List<Order> orders() {
        return orderClient.get()
                .uri("/orders")
                .retrieve()
                .body(new org.springframework.core.ParameterizedTypeReference<List<Order>>() {});
    }

    @GetMapping("/api/summary")
    public ResponseEntity<Map<String, Object>> summary() {
        List<Product> products = products();
        List<Order> orders = orders();

        Map<String, Object> result = new HashMap<>();
        result.put("productCount", products.size());
        result.put("orderCount", orders.size());
        result.put("products", products);
        result.put("orders", orders);

        return ResponseEntity.ok(result);
    }
}
