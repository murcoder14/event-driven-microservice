package org.muralis.service.model;

import java.time.LocalDateTime;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class S3FileUpload {
    private Long id;
    private String bucketName;
    private String objectKey;
    private String content;
    private LocalDateTime processedAt;
}
