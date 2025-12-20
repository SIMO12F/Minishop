package com.minishop.gateway;

public record Product(Long id, String name, String description, double price, int stock) {}
