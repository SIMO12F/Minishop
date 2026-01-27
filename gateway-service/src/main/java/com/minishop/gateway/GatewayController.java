package com.minishop.gateway;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestParam;
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
    public List<Product> products(
            @RequestParam(name = "work", defaultValue = "0") long workMs,
            @RequestParam(name = "tailEvery", defaultValue = "0") int tailEvery,
            @RequestParam(name = "tailExtra", defaultValue = "0") long tailExtraMs
    ) {
        // small gateway-side work too (helps scaling at gateway)
        WorkSimulator.burnCpuMs(workMs);
        WorkSimulator.maybeAddTail(tailEvery, tailExtraMs);

        return productClient.get()
                .uri("/products?work=" + workMs + "&tailEvery=" + tailEvery + "&tailExtra=" + tailExtraMs)
                .retrieve()
                .body(new org.springframework.core.ParameterizedTypeReference<List<Product>>() {});
    }

    @GetMapping("/api/orders")
    public List<Order> orders(
            @RequestParam(name = "work", defaultValue = "0") long workMs,
            @RequestParam(name = "tailEvery", defaultValue = "0") int tailEvery,
            @RequestParam(name = "tailExtra", defaultValue = "0") long tailExtraMs
    ) {
        WorkSimulator.burnCpuMs(workMs);
        WorkSimulator.maybeAddTail(tailEvery, tailExtraMs);

        return orderClient.get()
                .uri("/orders?work=" + workMs + "&tailEvery=" + tailEvery + "&tailExtra=" + tailExtraMs)
                .retrieve()
                .body(new org.springframework.core.ParameterizedTypeReference<List<Order>>() {});
    }

    @GetMapping("/api/summary")
    public ResponseEntity<Map<String, Object>> summary(
            @RequestParam(name = "work", defaultValue = "0") long workMs,
            @RequestParam(name = "tailEvery", defaultValue = "0") int tailEvery,
            @RequestParam(name = "tailExtra", defaultValue = "0") long tailExtraMs
    ) {
        WorkSimulator.burnCpuMs(workMs);
        WorkSimulator.maybeAddTail(tailEvery, tailExtraMs);

        List<Product> products = products(workMs, tailEvery, tailExtraMs);
        List<Order> orders = orders(workMs, tailEvery, tailExtraMs);

        Map<String, Object> result = new HashMap<>();
        result.put("productCount", products.size());
        result.put("orderCount", orders.size());
        result.put("products", products);
        result.put("orders", orders);

        return ResponseEntity.ok(result);
    }
}

