package org.muralis.service.client;

import io.github.resilience4j.circuitbreaker.annotation.CircuitBreaker;
import io.github.resilience4j.retry.annotation.Retry;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.muralis.service.exception.IrrecoverableApiException;
import org.muralis.service.exception.RecoverableApiException;
import org.muralis.service.model.GeocodingResponse;
import org.muralis.service.model.WeatherResponse;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatusCode;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestClient;

@Slf4j
@Component
@RequiredArgsConstructor
public class OpenMeteoClient {
    
    private final RestClient restClient;
    
    @Value("${app.openmeteo.geocoding-url}")
    private String geocodingUrl;
    
    @Value("${app.openmeteo.weather-url}")
    private String weatherUrl;
    
    @CircuitBreaker(name = "weatherApi", fallbackMethod = "getWeatherFallback")
    @Retry(name = "weatherApi")
    public WeatherResponse getWeatherForCity(String city, String country) {
        log.info("Fetching weather for city: {}, country: {}", city, country);
        
        // Step 1: Get coordinates from city name
        GeocodingResponse geocoding = getCoordinates(city);
        
        if (geocoding.getResults() == null || geocoding.getResults().isEmpty()) {
            throw new IrrecoverableApiException("City not found: " + city + ", " + country);
        }
        
        GeocodingResponse.Location location = geocoding.getResults().getFirst();
        log.info("Found coordinates for {}: lat={}, lon={}", city, location.getLatitude(), location.getLongitude());
        
        // Step 2: Get weather data
        return getWeather(location.getLatitude(), location.getLongitude());
    }

    private GeocodingResponse getCoordinates(String city) {
        try {
            return restClient.get()
                    .uri(geocodingUrl + "?name={city}&count=1&language=en&format=json", city)
                    .retrieve()
                    .onStatus(HttpStatusCode::is4xxClientError, (_, response) -> {
                        String msg = "Invalid geocoding request: " + response.getStatusCode();
                        throw new IrrecoverableApiException(msg);
                    })
                    .onStatus(HttpStatusCode::is5xxServerError, (_, response) -> {
                        String msg = "Geocoding service unavailable: "
                                + response.getStatusCode();
                        throw new RecoverableApiException(msg);
                    })
                    .body(GeocodingResponse.class);
        } catch (Exception e) {
            if (e instanceof IrrecoverableApiException || e instanceof RecoverableApiException) {
                throw e;
            }
            log.error("Network error calling geocoding API", e);
            throw new RecoverableApiException("Network error calling geocoding API", e);
        }
    }
    
    private WeatherResponse getWeather(Double latitude, Double longitude) {
        try {
            String uri = weatherUrl + "?latitude={lat}&longitude={lon}"
                    + "&current=temperature_2m,relative_humidity_2m,wind_speed_10m";
            return restClient.get()
                    .uri(uri, latitude, longitude)
                    .retrieve()
                    .onStatus(HttpStatusCode::is4xxClientError, (_, response) -> {
                        String msg = "Invalid weather request: " + response.getStatusCode();
                        throw new IrrecoverableApiException(msg);
                    })
                    .onStatus(HttpStatusCode::is5xxServerError, (_, response) -> {
                        String msg = "Weather service unavailable: "
                                + response.getStatusCode();
                        throw new RecoverableApiException(msg);
                    })
                    .body(WeatherResponse.class);
        } catch (Exception e) {
            if (e instanceof IrrecoverableApiException || e instanceof RecoverableApiException) {
                throw e;
            }
            log.error("Network error calling weather API", e);
            throw new RecoverableApiException("Network error calling weather API", e);
        }
    }
}
