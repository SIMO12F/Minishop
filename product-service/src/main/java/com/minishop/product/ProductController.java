package com.minishop.product;

import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.math.BigDecimal;
import java.util.*;
import java.util.concurrent.ConcurrentHashMap;

@RestController
@RequestMapping("/products")
public class ProductController {

    private final Map<Long, Product> products = new ConcurrentHashMap<>();

    public ProductController() {
        products.put(1L, new Product(1L, "Laptop", "Simple laptop", new BigDecimal("799.99"), 10));
        products.put(2L, new Product(2L, "Phone", "Smartphone", new BigDecimal("499.99"), 25));
        products.put(3L, new Product(3L, "Headphones", "Wireless headphones", new BigDecimal("99.99"), 50));
    }

    @GetMapping
    public List<Product> getAllProducts(
            @RequestParam(name = "work", defaultValue = "0") long workMs,
            @RequestParam(name = "tailEvery", defaultValue = "0") int tailEvery,
            @RequestParam(name = "tailExtra", defaultValue = "0") long tailExtraMs
    ) {
        WorkSimulator.burnCpuMs(workMs);
        WorkSimulator.maybeAddTail(tailEvery, tailExtraMs);
        return new ArrayList<>(products.values());
    }

    @GetMapping("/{id}")
    public ResponseEntity<Product> getProductById(
            @PathVariable Long id,
            @RequestParam(name = "work", defaultValue = "0") long workMs,
            @RequestParam(name = "tailEvery", defaultValue = "0") int tailEvery,
            @RequestParam(name = "tailExtra", defaultValue = "0") long tailExtraMs
    ) {
        WorkSimulator.burnCpuMs(workMs);
        WorkSimulator.maybeAddTail(tailEvery, tailExtraMs);

        Product product = products.get(id);
        if (product == null) {
            return ResponseEntity.notFound().build();
        }
        return ResponseEntity.ok(product);
    }

    @PostMapping
    public Product upsertProduct(@RequestBody Product product) {
        if (product.getId() == null) {
            long nextId = products.keySet().stream()
                    .mapToLong(Long::longValue)
                    .max()
                    .orElse(0L) + 1L;
            product.setId(nextId);
        }
        products.put(product.getId(), product);
        return product;
    }
}
