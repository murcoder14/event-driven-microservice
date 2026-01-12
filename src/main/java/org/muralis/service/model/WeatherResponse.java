package org.muralis.service.model;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import com.fasterxml.jackson.annotation.JsonProperty;
import lombok.Data;

@Data
@JsonIgnoreProperties(ignoreUnknown = true)
public class WeatherResponse {
    
    private Double latitude;
    private Double longitude;
    
    @JsonProperty("current")
    private CurrentWeather current;
    
    @Data
    @JsonIgnoreProperties(ignoreUnknown = true)
    public static class CurrentWeather {
        private String time;
        private Double temperature;
        
        @JsonProperty("temperature_2m")
        private Double temperature2m;
        
        @JsonProperty("wind_speed_10m")
        private Double windSpeed10m;
        
        @JsonProperty("relative_humidity_2m")
        private Integer relativeHumidity2m;
    }
}
