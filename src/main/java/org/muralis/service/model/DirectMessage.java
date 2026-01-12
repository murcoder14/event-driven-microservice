package org.muralis.service.model;

import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.time.LocalDateTime;

@Data
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class DirectMessage {

    private Long id;

    private String city;
    
    private String country;
    
    private String messageId;

    private LocalDateTime receivedAt;
}
