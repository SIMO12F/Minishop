package com.minishop.order;

import org.springframework.web.bind.annotation.*;

import java.util.List;

@RestController
@RequestMapping("/orders")
public class OrderController {

    @GetMapping
    public List<Order> getOrders(
            @RequestParam(name = "work", defaultValue = "0") long workMs,
            @RequestParam(name = "tailEvery", defaultValue = "0") int tailEvery,
            @RequestParam(name = "tailExtra", defaultValue = "0") long tailExtraMs
    ) {
        WorkSimulator.burnCpuMs(workMs);
        WorkSimulator.maybeAddTail(tailEvery, tailExtraMs);

        return List.of(
                new Order(1L, "Mohamed", 1299.99, "CREATED"),
                new Order(2L, "Sara", 499.50, "PAID"),
                new Order(3L, "Ali", 89.90, "SHIPPED")
        );
    }

    @GetMapping("/{id}")
    public Order getOrderById(
            @PathVariable Long id,
            @RequestParam(name = "work", defaultValue = "0") long workMs,
            @RequestParam(name = "tailEvery", defaultValue = "0") int tailEvery,
            @RequestParam(name = "tailExtra", defaultValue = "0") long tailExtraMs
    ) {
        WorkSimulator.burnCpuMs(workMs);
        WorkSimulator.maybeAddTail(tailEvery, tailExtraMs);

        return new Order(id, "DemoCustomer", 123.45, "CREATED");
    }
}

