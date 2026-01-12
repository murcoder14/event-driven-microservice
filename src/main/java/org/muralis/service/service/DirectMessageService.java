package org.muralis.service.service;

import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.muralis.service.client.OpenMeteoClient;
import org.muralis.service.model.DirectMessage;
import org.muralis.service.model.WeatherResponse;
import org.muralis.service.repository.DirectMessageRepository;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDateTime;

@Slf4j
@Service
@RequiredArgsConstructor
public class DirectMessageService {
    
    private final DirectMessageRepository repository;
    private final OpenMeteoClient weatherClient;
    
    @Transactional
    public void processMessage(String city, String country, String messageId) {
        // Idempotency check - do this FIRST before any external API calls
        if (repository.existsByMessageId(messageId)) {
            log.info("Message already processed (duplicate): messageId={}", messageId);
            return;
        }
        
        // Fetch weather data (may throw RecoverableApiException or IrrecoverableApiException)
        WeatherResponse weather = weatherClient.getWeatherForCity(city, country);
        
        // Log weather information
        log.info("Weather for {}, {}: Temp={}°C, Humidity={}%, Wind={} km/h",
                city, country,
                weather.getCurrent().getTemperature2m(),
                weather.getCurrent().getRelativeHumidity2m(),
                weather.getCurrent().getWindSpeed10m());
        
        // Save to database - wrap DB errors in DatabaseException
        try {
            DirectMessage message = DirectMessage.builder()
                    .city(city)
                    .country(country)
                    .messageId(messageId)
                    .receivedAt(LocalDateTime.now())
                    .build();
            
            repository.save(message);
            log.info("Saved message to database: city={}, country={}, messageId={}",
                    city, country, messageId);
        } catch (Exception e) {
            log.error("Database error while saving message: messageId={}", messageId, e);
            throw new org.muralis.service.exception.DatabaseException(
                    "Failed to save message to database", e);
        }
    }
}
