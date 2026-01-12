package org.muralis.service.repository;

import lombok.RequiredArgsConstructor;
import org.muralis.service.model.S3FileUpload;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Repository;

@Repository
@RequiredArgsConstructor
public class S3FileUploadRepository {

    private final JdbcTemplate jdbcTemplate;

    public void save(S3FileUpload upload) {
        String sql = "INSERT INTO s3_file_uploads (bucket_name, object_key, content, processed_at) VALUES (?, ?, ?, ?)";
        jdbcTemplate.update(sql, upload.getBucketName(), upload.getObjectKey(), upload.getContent(),
                upload.getProcessedAt());
    }
}
