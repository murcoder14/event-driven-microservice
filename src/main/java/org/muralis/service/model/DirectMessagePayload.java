package org.muralis.service.model;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;

@JsonIgnoreProperties(ignoreUnknown = true)
public record DirectMessagePayload(
    String city,
    String country,
    String messageId
) {}
