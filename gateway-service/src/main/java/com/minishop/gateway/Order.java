package com.minishop.gateway;

public record Order(Long id, String customer, double total, String status) {}
