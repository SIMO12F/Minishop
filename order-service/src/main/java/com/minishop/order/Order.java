package com.minishop.order;

public class Order {
    private Long id;
    private String customer;
    private Double total;
    private String status;

    public Order() {}

    public Order(Long id, String customer, Double total, String status) {
        this.id = id;
        this.customer = customer;
        this.total = total;
        this.status = status;
    }

    public Long getId() { return id; }
    public void setId(Long id) { this.id = id; }

    public String getCustomer() { return customer; }
    public void setCustomer(String customer) { this.customer = customer; }

    public Double getTotal() { return total; }
    public void setTotal(Double total) { this.total = total; }

    public String getStatus() { return status; }
    public void setStatus(String status) { this.status = status; }
}

